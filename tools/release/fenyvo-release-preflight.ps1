param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

Write-Host '=== FENYVO RELEASE PREFLIGHT ===' -ForegroundColor Cyan

$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
$guard = Join-Path $ProjectRoot 'tools\release\localization_guard.ps1'

if (!(Test-Path -LiteralPath $pubspec)) {
    throw 'PROJECT NOT FOUND'
}

if (!(Test-Path -LiteralPath $guard)) {
    throw 'LOCALIZATION GUARD NOT FOUND'
}

$versionLine = Get-Content -LiteralPath $pubspec |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1

if (!$versionLine) {
    throw 'PROJECT VERSION NOT FOUND'
}

Write-Host "PROJECT $versionLine"

Write-Host 'CHECK: LOCALIZATION GUARD'

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $guard -ProjectRoot $ProjectRoot

if ($LASTEXITCODE -ne 0) {
    throw 'RELEASE BLOCKED: LOCALIZATION CHECK FAILED'
}

Write-Host ''
Write-Host '=== FENYVO RELEASE PREFLIGHT PASSED ===' -ForegroundColor Green
Write-Host 'LOCALIZATION: PASSED'
Write-Host 'ANDROID BUILD: NOT STARTED'
Write-Host 'WINDOWS BUILD: NOT STARTED'
Write-Host 'DEPLOYMENT: NOT STARTED'