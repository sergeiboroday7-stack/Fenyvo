param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$install = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$backup = $install + '.rollback'

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

if ([IO.Directory]::Exists($install)) {
    $installedExe = Join-Path $install 'fenyvo.exe'

    if (-not [IO.File]::Exists($installedExe)) {
        throw 'Installation exists but fenyvo.exe is missing; manual recovery required'
    }

    Write-Host 'INSTALLATION EXISTS - NO RESTORE NEEDED'
    exit 0
}

if (-not [IO.Directory]::Exists($backup)) {
    Write-Host 'NO ROLLBACK BACKUP FOUND'
    exit 0
}

$backupExe = Join-Path $backup 'fenyvo.exe'

if (-not [IO.File]::Exists($backupExe)) {
    throw 'Rollback backup does not contain fenyvo.exe'
}

[IO.Directory]::Move($backup, $install)

if (-not [IO.File]::Exists((Join-Path $install 'fenyvo.exe'))) {
    throw 'Recovered executable verification failed'
}

Write-Host 'FENYVO PREVIOUS VERSION RESTORED' -ForegroundColor Green
