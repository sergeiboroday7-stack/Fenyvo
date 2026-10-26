param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [Parameter(Mandatory = $true)]
    [string]$StagedPath,

    [Parameter(Mandatory = $true)]
    [int]$AppProcessId,

    [Parameter(Mandatory = $true)]
    [long]$AppProcessStartTicks,

    [switch]$ExecuteController
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$install = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$staged = [IO.Path]::GetFullPath($StagedPath).TrimEnd('\')

if ([IO.Path]::GetFileName($install) -cne 'Fenyvo') {
    throw 'Invalid installation directory'
}

if (-not [IO.Directory]::Exists($install)) {
    throw 'Installation directory missing'
}

if (-not [IO.Directory]::Exists($staged)) {
    throw 'Staged update missing'
}

if ($AppProcessId -le 0 -or $AppProcessStartTicks -le 0) {
    throw 'Invalid process identity'
}

$expectedStage = $install + '.staged'
$backup = $install + '.rollback'
$failed = $install + '.failed-update'

if (-not [string]::Equals(
    $staged,
    $expectedStage,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Staged directory must be adjacent to installation'
}

if ([IO.Directory]::Exists($backup) -or
    [IO.File]::Exists($backup)) {
    throw 'Previous rollback backup exists; update refused'
}

if ([IO.Directory]::Exists($failed) -or
    [IO.File]::Exists($failed)) {
    throw 'Previous failed update exists; update refused'
}

foreach ($candidate in @($install, $staged, $backup, $failed)) {
    $current = $candidate

    while ($true) {
        if ([IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force

            if (($item.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point rejected: $current"
            }
        }
        elseif ([IO.File]::Exists($current)) {
            throw "File in directory path: $current"
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
}

Write-Host 'STAGING PATH VERIFIED'
Write-Host 'PREVIOUS UPDATE STATE VERIFIED'
$source = Split-Path -Parent $MyInvocation.MyCommand.Path

$scripts = @(
    'Apply-FenyvoUpdate.ps1',
    'Rollback-FenyvoUpdate.ps1',
    'Test-FenyvoLaunch.ps1',
    'Complete-FenyvoUpdate.ps1'
)

$work = Join-Path $env:TEMP (
    'fenyvo-update-runner-' + [guid]::NewGuid().ToString('N')
)

New-Item -ItemType Directory -Path $work -ErrorAction Stop |
    Out-Null

try {
    foreach ($name in $scripts) {
        $sourceFile = Join-Path $source $name
        $targetFile = Join-Path $work $name

        if (-not [IO.File]::Exists($sourceFile)) {
            throw "Update component missing: $name"
        }

        Copy-Item -LiteralPath $sourceFile `
            -Destination $targetFile -ErrorAction Stop
    }

    $controller = Join-Path $work 'Complete-FenyvoUpdate.ps1'

    Write-Host 'INDEPENDENT UPDATE CONTROLLER PREPARED'
    Write-Host "CONTROLLER: $controller"

    if (-not $ExecuteController) {
        Write-Host 'CONTROLLER EXECUTION DISABLED'
        return
    }

    Write-Host 'STARTING INDEPENDENT UPDATE CONTROLLER'

    $standardOutputLog = Join-Path $work 'controller.stdout.log'
    $standardErrorLog = Join-Path $work 'controller.stderr.log'
    $controllerReadyFile = Join-Path $work 'controller.ready'

    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $controller + '"'),
        '-InstallPath', ('"' + $install + '"'),
        '-StagedPath', ('"' + $staged + '"'),
        '-AppProcessId', [string]$AppProcessId,
        '-AppProcessStartTicks', [string]$AppProcessStartTicks,
        '-ControllerReadyFile', ('"' + $controllerReadyFile + '"')
    )

    $powershellExe = Join-Path $env:SystemRoot `
        'System32\WindowsPowerShell\v1.0\powershell.exe'

    if (-not [IO.File]::Exists($powershellExe)) {
        $powershellExe = (Get-Process -Id $PID -ErrorAction Stop).Path
    }

    if (-not [IO.File]::Exists($powershellExe)) {
        throw 'PowerShell executable not found'
    }

    $process = Start-Process `
        -FilePath $powershellExe `
        -ArgumentList $arguments `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $standardOutputLog `
        -RedirectStandardError $standardErrorLog

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(20)

    while (-not [IO.File]::Exists($controllerReadyFile)) {
        $process.Refresh()

        if ($process.HasExited) {
            $details = ''

            foreach ($logPath in @($standardOutputLog, $standardErrorLog)) {
                if ([IO.File]::Exists($logPath)) {
                    $details += [IO.File]::ReadAllText($logPath)
                }
            }

            throw "Update controller exited before readiness: $details"
        }

        if ([DateTime]::UtcNow -ge $readyDeadline) {
            $process.Kill()
            [void]$process.WaitForExit(10000)
            throw 'Update controller readiness timed out'
        }

        Start-Sleep -Milliseconds 100
    }

    Write-Output "UPDATE CONTROLLER PID: $($process.Id)"
    Write-Output "UPDATE CONTROLLER OUTPUT: $standardOutputLog"
    Write-Output "UPDATE CONTROLLER ERROR: $standardErrorLog"
    Write-Host 'INDEPENDENT UPDATE CONTROLLER STARTED'
}
catch {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }

    throw
}
