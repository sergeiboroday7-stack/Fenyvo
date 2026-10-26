param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$bundle = [IO.Path]::GetFullPath($BundlePath).TrimEnd('\')
$sourceRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..')
).TrimEnd('\')
$installerSource = Join-Path $sourceRoot 'windows\installer'
$previousNoZoneChecks = $env:SEE_MASK_NOZONECHECKS
$env:SEE_MASK_NOZONECHECKS = '1'

if (-not [IO.File]::Exists((Join-Path $bundle 'fenyvo.exe'))) {
    throw 'Runnable Windows bundle not found'
}

if (@(Get-Process -Name 'fenyvo' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close the real FENYVO before running updater transaction tests'
}

$testParent = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'build'))
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$env:TEMP = $testParent
$env:TMP = $testParent
$tempRoot = [IO.Path]::GetFullPath((Join-Path $testParent (
    'fenyvo-updater-tests-' + [guid]::NewGuid().ToString('N')
)))
$expectedTempRoot = $testParent.TrimEnd('\') + '\'

if (-not $tempRoot.StartsWith(
    $expectedTempRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Unsafe test directory'
}

function Copy-TestBundle {
    param(
        [string]$Destination,
        [string]$Marker
    )

    Copy-Item -LiteralPath $bundle -Destination $Destination -Recurse
    Get-ChildItem -LiteralPath $Destination -File -Recurse |
        Unblock-File -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $Destination 'transaction-marker.txt') `
        -Value $Marker -NoNewline -Encoding UTF8

    Get-ChildItem -LiteralPath $installerSource -Filter '*.ps1' | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Force
    }
}

function Get-ControllerProcess {
    param([string[]]$OutputLines)

    $pidLine = $OutputLines |
        Where-Object { $_ -match '^UPDATE CONTROLLER PID: [0-9]+$' } |
        Select-Object -Last 1

    if ($null -eq $pidLine) {
        throw 'Updater controller PID was not reported'
    }

    $outputLine = $OutputLines |
        Where-Object { $_ -match '^UPDATE CONTROLLER OUTPUT: .+$' } |
        Select-Object -Last 1
    $errorLine = $OutputLines |
        Where-Object { $_ -match '^UPDATE CONTROLLER ERROR: .+$' } |
        Select-Object -Last 1

    if ($null -eq $outputLine -or $null -eq $errorLine) {
        throw 'Updater controller log paths were not reported'
    }

    $controllerId = [int](($pidLine -split ':', 2)[1].Trim())
    return [pscustomobject]@{
        Process = Get-Process -Id $controllerId -ErrorAction Stop
        OutputLog = ($outputLine -split ': ', 2)[1]
        ErrorLog = ($errorLine -split ': ', 2)[1]
    }
}

function Write-ControllerLogs {
    param($Controller)

    if ([IO.File]::Exists($Controller.OutputLog)) {
        Get-Content -LiteralPath $Controller.OutputLog
    }

    if ([IO.File]::Exists($Controller.ErrorLog)) {
        Get-Content -LiteralPath $Controller.ErrorLog
    }
}

function Start-TestTransaction {
    param(
        [string]$InstallPath,
        [string]$StagedPath
    )

    $oldApp = Start-Process `
        -FilePath (Join-Path $InstallPath 'fenyvo.exe') `
        -WorkingDirectory $InstallPath -PassThru

    Start-Sleep -Seconds 2
    $oldApp.Refresh()

    if ($oldApp.HasExited) {
        throw 'Test FENYVO failed to start'
    }

    $startTicks = $oldApp.StartTime.ToUniversalTime().Ticks
    $output = @(
        & (Join-Path $InstallPath 'Start-FenyvoUpdate.ps1') `
            -InstallPath $InstallPath `
            -StagedPath $StagedPath `
            -AppProcessId $oldApp.Id `
            -AppProcessStartTicks $startTicks `
            -ExecuteController
    )

    $controller = Get-ControllerProcess -OutputLines $output
    Stop-Process -Id $oldApp.Id -Force
    $oldApp.WaitForExit()
    $oldApp.Dispose()

    return $controller
}

function Stop-TestFenyvo {
    param([string]$InstallPath)

    $expectedExe = [IO.Path]::GetFullPath(
        (Join-Path $InstallPath 'fenyvo.exe')
    )

    @(Get-Process -Name 'fenyvo' -ErrorAction SilentlyContinue) |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Path) -and
            [string]::Equals(
                [IO.Path]::GetFullPath($_.Path),
                $expectedExe,
                [StringComparison]::OrdinalIgnoreCase
            )
        } |
        ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
}

New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Write-Host '=== SUCCESS TRANSACTION ==='
    $successParent = Join-Path $tempRoot 'success'
    $successInstall = Join-Path $successParent 'Fenyvo'
    $successStaged = $successInstall + '.staged'
    New-Item -ItemType Directory -Path $successParent | Out-Null
    Copy-TestBundle -Destination $successInstall -Marker 'old'
    Copy-TestBundle -Destination $successStaged -Marker 'new'

    $successController = Start-TestTransaction `
        -InstallPath $successInstall -StagedPath $successStaged
    if (-not $successController.Process.WaitForExit(60000)) {
        Stop-Process -Id $successController.Process.Id -Force
        throw 'Successful update controller timed out'
    }
    Write-ControllerLogs -Controller $successController
    $successController.Process.Dispose()

    if ((Get-Content (Join-Path $successInstall 'transaction-marker.txt') -Raw) -ne 'new') {
        throw 'Successful update did not install the staged bundle'
    }

    if ([IO.Directory]::Exists($successInstall + '.rollback')) {
        throw 'Successful update left a rollback directory'
    }

    Stop-TestFenyvo -InstallPath $successInstall
    Write-Host 'SUCCESS TRANSACTION VERIFIED' -ForegroundColor Green

    Write-Host '=== FAILED-LAUNCH ROLLBACK ==='
    $failureParent = Join-Path $tempRoot 'failure'
    $failureInstall = Join-Path $failureParent 'Fenyvo'
    $failureStaged = $failureInstall + '.staged'
    New-Item -ItemType Directory -Path $failureParent | Out-Null
    Copy-TestBundle -Destination $failureInstall -Marker 'old'
    New-Item -ItemType Directory -Path $failureStaged | Out-Null
    Copy-Item -LiteralPath "$env:SystemRoot\System32\where.exe" `
        -Destination (Join-Path $failureStaged 'fenyvo.exe')
    Set-Content -LiteralPath (Join-Path $failureStaged 'transaction-marker.txt') `
        -Value 'broken' -NoNewline -Encoding UTF8

    $failureController = Start-TestTransaction `
        -InstallPath $failureInstall -StagedPath $failureStaged
    if (-not $failureController.Process.WaitForExit(60000)) {
        Stop-Process -Id $failureController.Process.Id -Force
        throw 'Rollback update controller timed out'
    }
    Write-ControllerLogs -Controller $failureController
    $failureController.Process.Dispose()

    if ((Get-Content (Join-Path $failureInstall 'transaction-marker.txt') -Raw) -ne 'old') {
        throw 'Rollback did not restore the previous bundle'
    }

    if ([IO.Directory]::Exists($failureInstall + '.rollback')) {
        throw 'Rollback backup still exists after restoration'
    }

    if (-not [IO.Directory]::Exists($failureInstall + '.failed-update')) {
        throw 'Failed update was not preserved for diagnostics'
    }

    Stop-TestFenyvo -InstallPath $failureInstall
    Write-Host 'FAILED-LAUNCH ROLLBACK VERIFIED' -ForegroundColor Green
}
finally {
    Stop-TestFenyvo -InstallPath (Join-Path $tempRoot 'success\Fenyvo')
    Stop-TestFenyvo -InstallPath (Join-Path $tempRoot 'failure\Fenyvo')

    if ([IO.Directory]::Exists($tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }

    if ($null -eq $previousNoZoneChecks) {
        Remove-Item Env:SEE_MASK_NOZONECHECKS -ErrorAction SilentlyContinue
    }
    else {
        $env:SEE_MASK_NOZONECHECKS = $previousNoZoneChecks
    }

    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}

Write-Host 'ALL WINDOWS UPDATE TRANSACTION TESTS PASSED' -ForegroundColor Green
