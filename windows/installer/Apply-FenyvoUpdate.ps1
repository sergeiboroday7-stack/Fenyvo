param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [Parameter(Mandatory = $true)]
    [string]$StagedPath,

    [Parameter(Mandatory = $true)]
    [int]$AppProcessId,

    [Parameter(Mandatory = $true)]
    [long]$AppProcessStartTicks,

    [string]$ControllerReadyFile,

    [switch]$SimulateFailureAfterBackup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$install = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$staged = [IO.Path]::GetFullPath($StagedPath).TrimEnd('\')

if ($AppProcessId -le 0) {
    throw 'Invalid application process ID'
}

if ([IO.Path]::GetFileName($install) -cne 'Fenyvo') {
    throw 'Installation directory must be named Fenyvo'
}

function Assert-NoReparsePoint {
    param([string]$PathToCheck)

    $current = [IO.Path]::GetFullPath($PathToCheck)

    while ($true) {
        if ([IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force

            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point rejected: $current"
            }
        }
        elseif ([IO.File]::Exists($current)) {
            throw "File found in directory path: $current"
        }

        $parentPath = [IO.Path]::GetDirectoryName($current)

        if ([string]::IsNullOrEmpty($parentPath) -or
            [string]::Equals(
                $parentPath,
                $current,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            break
        }

        $current = $parentPath
    }
}

Assert-NoReparsePoint -PathToCheck $install
Assert-NoReparsePoint -PathToCheck $staged
Assert-NoReparsePoint -PathToCheck ($install + '.rollback')

if (-not [IO.Directory]::Exists($install)) {
    throw 'Installation directory not found'
}

if (-not [IO.Directory]::Exists($staged)) {
    throw 'Staged update directory not found'
}

if (-not [IO.File]::Exists((Join-Path $install 'fenyvo.exe'))) {
    throw 'Current FENYVO executable not found'
}

if (-not [IO.File]::Exists((Join-Path $staged 'fenyvo.exe'))) {
    throw 'New FENYVO executable not found'
}

$parent = [IO.Path]::GetDirectoryName($install)
$backup = $install + '.rollback'

if (-not [string]::Equals(
    [IO.Path]::GetDirectoryName($staged),
    $parent,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Staging directory must be next to installation directory'
}

if ([IO.Directory]::Exists($backup) -or
    [IO.File]::Exists($backup)) {
    throw 'Previous rollback directory exists; refusing to overwrite'
}

if ([string]::Equals(
    $staged,
    $install,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Staging directory matches installation directory'
}

if ($AppProcessStartTicks -le 0) {
    throw 'Invalid application process start time'
}

$expectedExe = [IO.Path]::GetFullPath(
    (Join-Path $install 'fenyvo.exe')
)

$appProcess = Get-Process -Id $AppProcessId -ErrorAction Stop

if ($null -eq $appProcess) {
    throw 'Application process not found'
}

if ([string]::IsNullOrWhiteSpace($appProcess.Path)) {
    throw 'Cannot verify application process path'
}

$actualExe = [IO.Path]::GetFullPath($appProcess.Path)

if (-not [string]::Equals(
    $actualExe,
    $expectedExe,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Application process does not belong to installation'
}

$actualStartTicks = $appProcess.StartTime.ToUniversalTime().Ticks

$startTimeDifference = [Math]::Abs(
    [decimal]$actualStartTicks - [decimal]$AppProcessStartTicks
)

# Windows process APIs can differ slightly in timestamp precision.
# One millisecond equals 10,000 DateTime ticks.
if ($startTimeDifference -gt 10000) {
    throw 'Application process start time mismatch'
}

Write-Host 'APPLICATION PROCESS IDENTITY VERIFIED'

Write-Host 'WAITING FOR FENYVO TO EXIT'

# Retain a handle to the verified process.
# PID reuse cannot substitute another process for this handle.
$verifiedProcess = Get-Process -Id $AppProcessId -ErrorAction Stop

$verifiedStartTicks = $verifiedProcess.StartTime.ToUniversalTime().Ticks

$handleDifference = [Math]::Abs(
    [decimal]$verifiedStartTicks - [decimal]$AppProcessStartTicks
)

if ($handleDifference -gt 10000) {
    throw 'Application process changed before wait'
}

# Acquire the process handle before waiting for it to exit.
$null = $verifiedProcess.Handle

if (-not [string]::IsNullOrWhiteSpace($ControllerReadyFile)) {
    $readyPath = [IO.Path]::GetFullPath($ControllerReadyFile)
    $readyParent = [IO.Path]::GetDirectoryName($readyPath)

    if (-not [IO.Directory]::Exists($readyParent)) {
        throw 'Controller readiness directory does not exist'
    }

    [IO.File]::WriteAllText($readyPath, 'ready')
    Write-Host 'UPDATE CONTROLLER READY'
}

if (-not $verifiedProcess.WaitForExit(90000)) {
    throw 'FENYVO did not exit within 90 seconds'
}

Write-Host 'APPLICATION PROCESS EXITED'

$movedOld = $false

try {
    [IO.Directory]::Move($install, $backup)
    $movedOld = $true

    if ($SimulateFailureAfterBackup) {
        throw 'SIMULATED FAILURE AFTER BACKUP'
    }

    [IO.Directory]::Move($staged, $install)

    if (-not [IO.File]::Exists((Join-Path $install 'fenyvo.exe'))) {
        throw 'Updated executable missing after installation'
    }

    Write-Host 'UPDATE FILES APPLIED' -ForegroundColor Green
    Write-Host "ROLLBACK BACKUP: $backup"
}
catch {
    $originalError = $_

    if ($movedOld) {
        $failed = $install + '.failed-update'

        Assert-NoReparsePoint -PathToCheck $install
        Assert-NoReparsePoint -PathToCheck $backup
        Assert-NoReparsePoint -PathToCheck $failed

        if ([IO.Directory]::Exists($install)) {
            if ([IO.Directory]::Exists($failed) -or
                [IO.File]::Exists($failed)) {
                throw 'Failed-update directory already exists; manual recovery required'
            }

            [IO.Directory]::Move($install, $failed)
            Write-Host "FAILED UPDATE PRESERVED: $failed"
        }

        if (-not [IO.Directory]::Exists($backup)) {
            throw 'Rollback backup missing; manual recovery required'
        }

        [IO.Directory]::Move($backup, $install)
        Write-Host 'PREVIOUS VERSION RESTORED' -ForegroundColor Yellow
    }

    throw $originalError
}
