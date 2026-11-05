param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [Parameter(Mandatory = $true)]
    [string]$StagedPath,

    [Parameter(Mandatory = $true)]
    [int]$AppProcessId,

    [Parameter(Mandatory = $true)]
    [long]$AppProcessStartTicks,

    [Parameter(Mandatory = $true)]
    [string]$ControllerReadyFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Record controller output independently of the launching process.
# The transcript is stored beside the detached controller scripts.
$transcriptPath = Join-Path $PSScriptRoot 'controller.transcript.log'
Start-Transcript -LiteralPath $transcriptPath -Force -ErrorAction Stop | Out-Null


$install = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$staged = [IO.Path]::GetFullPath($StagedPath).TrimEnd('\')

if ([IO.Path]::GetFileName($install) -cne 'Fenyvo') {
    throw 'Invalid installation directory'
}

if (-not [IO.Directory]::Exists($install)) {
    throw 'Installation directory not found'
}

if (-not [IO.Directory]::Exists($staged)) {
    throw 'Staged directory not found'
}

if ($AppProcessId -le 0 -or $AppProcessStartTicks -le 0) {
    throw 'Invalid application process identity'
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$apply = Join-Path $scriptDir 'Apply-FenyvoUpdate.ps1'
$launch = Join-Path $scriptDir 'Test-FenyvoLaunch.ps1'
$rollback = Join-Path $scriptDir 'Rollback-FenyvoUpdate.ps1'

foreach ($script in @($apply, $launch, $rollback)) {
    if (-not [IO.File]::Exists($script)) {
        throw "Required update component missing: $script"
    }
}

Write-Host 'UPDATE COMPONENTS VERIFIED'

Write-Host 'STARTING UPDATE TRANSACTION'

try {
    & $apply `
        -InstallPath $install `
        -StagedPath $staged `
        -AppProcessId $AppProcessId `
        -AppProcessStartTicks $AppProcessStartTicks `
        -ControllerReadyFile $ControllerReadyFile
}
catch {
    $applyError = $_

    if ([IO.File]::Exists((Join-Path $install 'fenyvo.exe'))) {
        try {
            & $launch `
                -InstallPath $install `
                -ObservationSeconds 15
        }
        catch {
            Write-Warning "Could not restart FENYVO after apply failure: $($_.Exception.Message)"
        }
    }

    throw $applyError
}

Write-Host 'UPDATE FILES INSTALLED'

try {
    & $launch `
        -InstallPath $install `
        -ObservationSeconds 15 -RequireFlutterReady
}
catch {
    $launchError = $_
    Write-Host 'UPDATED FENYVO FAILED TO START' -ForegroundColor Yellow
    Write-Host 'STARTING AUTOMATIC ROLLBACK'

    try {
        & $rollback -InstallPath $install
    }
    catch {
        throw "Automatic rollback failed: $($_.Exception.Message)"
    }

    try {
        & $launch `
            -InstallPath $install `
            -ObservationSeconds 15
    }
    catch {
        throw "Previous version was restored but failed to start: $($_.Exception.Message)"
    }

    throw "Update was rolled back because the new version failed to start: $($launchError.Exception.Message)"
}

Write-Host 'UPDATED FENYVO LAUNCH VERIFIED'

$backup = $install + '.rollback'

if ([IO.Directory]::Exists($backup)) {
    # Check the active backup and every parent for reparse points.
    $current = $backup

    while ($true) {
        if ([IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force

            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point rejected during cleanup: $current"
            }
        }
        elseif ([IO.File]::Exists($current)) {
            throw "File found in cleanup path: $current"
        }

        $parent = [IO.Path]::GetDirectoryName($current)

        if ([string]::IsNullOrEmpty($parent) -or
            [string]::Equals(
                $parent,
                $current,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            break
        }

        $current = $parent
    }

    if (-not [IO.File]::Exists((Join-Path $backup 'fenyvo.exe'))) {
        throw 'Rollback backup executable missing; cleanup refused'
    }

    # The new build already passed its Flutter first-frame check.
    # Move the previous build out of the active rollback path first.
    $archived = $install + '.rollback-completed-' +
        [guid]::NewGuid().ToString('N')

    if ([IO.Directory]::Exists($archived) -or
        [IO.File]::Exists($archived)) {
        throw 'Completed rollback archive destination already exists'
    }

    [IO.Directory]::Move($backup, $archived)

    Write-Host 'ROLLBACK BACKUP MOVED OUT OF ACTIVE PATH'

    # Keep the completed backup for recovery instead of recursively deleting it.
    # The active .rollback path is already free for the next update.
    Write-Host "COMPLETED ROLLBACK BACKUP PRESERVED: $archived"
}
elseif ([IO.File]::Exists($backup)) {
    throw 'Rollback path is a file; cleanup refused'
}

Write-Host 'UPDATE TRANSACTION COMPLETE' -ForegroundColor Green
