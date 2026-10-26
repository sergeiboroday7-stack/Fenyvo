param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$install = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$backup = $install + '.rollback'
$failed = $install + '.failed-update'

if ([IO.Path]::GetFileName($install) -cne 'Fenyvo') {
    throw 'Installation directory must be named Fenyvo'
}

function Assert-SafePath {
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

Assert-SafePath $install
Assert-SafePath $backup
Assert-SafePath $failed

if (-not [IO.Directory]::Exists($backup)) {
    throw 'Rollback backup not found'
}

if (-not [IO.File]::Exists((Join-Path $backup 'fenyvo.exe'))) {
    throw 'Rollback backup executable missing'
}

if ([IO.Directory]::Exists($failed) -or [IO.File]::Exists($failed)) {
    throw 'Failed-update directory already exists; manual recovery required'
}

if ([IO.Directory]::Exists($install)) {
    $exe = [IO.Path]::GetFullPath((Join-Path $install 'fenyvo.exe'))

    $running = @(Get-Process -Name 'fenyvo' -ErrorAction SilentlyContinue)

    foreach ($app in $running) {
        if ([string]::IsNullOrWhiteSpace($app.Path)) {
            throw 'Cannot verify running process path'
        }

        if ([string]::Equals(
            [IO.Path]::GetFullPath($app.Path),
            $exe,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw 'FENYVO is still running; rollback refused'
        }
    }

    [IO.Directory]::Move($install, $failed)
    Write-Host "FAILED UPDATE PRESERVED: $failed"
}

[IO.Directory]::Move($backup, $install)

Write-Host 'PREVIOUS VERSION RESTORED' -ForegroundColor Green
