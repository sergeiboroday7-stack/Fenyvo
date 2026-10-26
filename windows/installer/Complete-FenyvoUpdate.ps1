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
        -ObservationSeconds 15
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
    try {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
        Write-Host 'ROLLBACK BACKUP CLEANED'
    }
    catch {
        Write-Warning "Update succeeded but rollback backup could not be removed: $($_.Exception.Message)"
    }
}

Write-Host 'UPDATE TRANSACTION COMPLETE' -ForegroundColor Green
