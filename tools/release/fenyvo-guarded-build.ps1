param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Android', 'Windows')]
    [string]$Platform,

    [switch]$Build
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$preflight = Join-Path $root 'tools\release\fenyvo-release-preflight.ps1'
$flutter = 'C:\src\flutter\bin\flutter.bat'

Write-Host '=== FENYVO GUARDED BUILD ===' -ForegroundColor Cyan
Write-Host "PLATFORM: $Platform"

if (!(Test-Path -LiteralPath $preflight)) {
    throw 'PREFLIGHT NOT FOUND - BUILD BLOCKED'
}

Write-Host 'CHECK: RELEASE PREFLIGHT'

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $preflight -ProjectRoot $root

if ($LASTEXITCODE -ne 0) {
    throw 'BUILD BLOCKED: LOCALIZATION PREFLIGHT FAILED'
}

Write-Host 'PREFLIGHT: PASSED' -ForegroundColor Green

if (!$Build) {
    Write-Host 'BUILD: NOT REQUESTED'
    Write-Host '=== GUARDED BUILD DRY RUN PASSED ===' -ForegroundColor Green
    return
}

if (!(Test-Path -LiteralPath $flutter)) {
    throw 'FLUTTER SDK NOT FOUND'
}

Push-Location -LiteralPath $root

try {
    if ($Platform -eq 'Android') {
        Write-Host 'BUILDING ANDROID ARM64 RELEASE'
        & $flutter build apk --release --target-platform android-arm64
    }
    else {
        Write-Host 'BUILDING WINDOWS RELEASE'
        & $flutter build windows --release
    }

    if ($LASTEXITCODE -ne 0) {
        throw "FLUTTER BUILD FAILED: $Platform"
    }

    Write-Host '=== GUARDED BUILD PASSED ===' -ForegroundColor Green
}
finally {
    Pop-Location
}