$ErrorActionPreference = 'Stop'

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Fenyvo'
$TargetExe = Join-Path $InstallDir 'fenyvo.exe'

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'fenyvo.exe'))) {
  throw 'fenyvo.exe was not found next to the installer.'
}

$sourceFull = [IO.Path]::GetFullPath($SourceDir).TrimEnd('\')
$installFull = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')

if (-not $sourceFull.Equals($installFull, [StringComparison]::OrdinalIgnoreCase)) {
  Get-Process -Name 'fenyvo' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Get-ChildItem -LiteralPath $SourceDir -Force |
    Where-Object { $_.Name -ne 'Install-Fenyvo.ps1' } |
    Copy-Item -Destination $InstallDir -Recurse -Force
  Copy-Item -LiteralPath $MyInvocation.MyCommand.Path `
    -Destination (Join-Path $InstallDir 'Install-Fenyvo.ps1') -Force
}

if (-not (Test-Path -LiteralPath $TargetExe)) {
  throw "Installed executable was not found: $TargetExe"
}

Get-ChildItem -LiteralPath $InstallDir -Recurse -File -ErrorAction SilentlyContinue |
  Unblock-File -ErrorAction SilentlyContinue

$Shell = New-Object -ComObject WScript.Shell
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$ShortcutTargets = @(
  (Join-Path $DesktopDir 'Fenyvo.lnk'),
  (Join-Path ([Environment]::GetFolderPath('Programs')) 'Fenyvo.lnk')
)

foreach ($ExistingLink in Get-ChildItem -LiteralPath $DesktopDir -Filter '*.lnk' -File -ErrorAction SilentlyContinue) {
  try {
    $ExistingTarget = $Shell.CreateShortcut($ExistingLink.FullName).TargetPath
    $ExistingName = Split-Path -Leaf $ExistingTarget
    if ($ExistingName -in @('fenyvo.exe', 'spartan_chat_final.exe', 'spartan_chat.exe')) {
      $ShortcutTargets += $ExistingLink.FullName
    }
  } catch {
    # An unrelated or broken shortcut must not block the Fenyvo update.
  }
}
$ShortcutTargets = $ShortcutTargets | Select-Object -Unique

foreach ($ShortcutPath in $ShortcutTargets) {
  $Shortcut = $Shell.CreateShortcut($ShortcutPath)
  $Shortcut.TargetPath = $TargetExe
  $Shortcut.WorkingDirectory = $InstallDir
  $Shortcut.IconLocation = "$TargetExe,0"
  $Shortcut.Description = 'Fenyvo messenger'
  $Shortcut.Save()
}

Write-Host "Fenyvo installed: $InstallDir"
Write-Host 'Desktop and Start Menu shortcuts updated.'
Start-Process -FilePath $TargetExe -WorkingDirectory $InstallDir
