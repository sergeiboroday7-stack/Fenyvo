param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [ValidateRange(1, 30)]
    [int]$ObservationSeconds = 5,

    [switch]$RequireFlutterReady
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$install = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$exe = Join-Path $install 'fenyvo.exe'

if ([IO.Path]::GetFileName($install) -cne 'Fenyvo') {
    throw 'Installation directory must be named Fenyvo'
}

if (-not [IO.File]::Exists($exe)) {
    throw 'FENYVO executable not found'
}

$running = @(Get-Process -Name 'fenyvo' -ErrorAction SilentlyContinue)

if ($running.Count -gt 0) {
    throw 'Another FENYVO process is running; launch test refused'
}

$readyFile = $null
$arguments = @()

if ($RequireFlutterReady) {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    $token = -join ($bytes | ForEach-Object { $_.ToString('x2') })

    $readyFile = Join-Path $env:TEMP (
        'fenyvo-ready-' + [guid]::NewGuid().ToString('N') + '.txt'
    )

    $arguments = @(
        "--fenyvo-update-token=$token",
        "--fenyvo-update-ready-file=$readyFile"
    )
}

$process = $null
$launchVerified = $false
$previousReadyToken = $env:FENYVO_UPDATE_TOKEN
$previousReadyFile = $env:FENYVO_UPDATE_READY_FILE

try {
    $startOptions = @{
        FilePath = $exe
        WorkingDirectory = $install
        PassThru = $true
    }

    if ($arguments.Count -gt 0) {
        $startOptions.ArgumentList = $arguments
        $env:FENYVO_UPDATE_TOKEN = $token
        $env:FENYVO_UPDATE_READY_FILE = $readyFile
    }

    $process = Start-Process @startOptions
    $expectedPid = $process.Id
    $deadline = [DateTime]::UtcNow.AddSeconds($ObservationSeconds)
    $confirmed = $false

    do {
        Start-Sleep -Milliseconds 200
        $process.Refresh()

        if ($process.HasExited) {
            throw 'FENYVO exited during launch observation'
        }

        if ($RequireFlutterReady -and
            [IO.File]::Exists($readyFile)) {

            $actualToken = [IO.File]::ReadAllText($readyFile).Trim()

            if ($actualToken -ne $token) {
                throw 'Invalid Flutter readiness token'
            }

            $confirmed = $true
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)

    $process.Refresh()

    if ($process.HasExited) {
        throw 'FENYVO exited during launch observation'
    }

    $actual = Get-Process -Id $expectedPid -ErrorAction Stop

    if ($null -eq $actual -or
        [string]::IsNullOrWhiteSpace($actual.Path)) {
        throw 'Cannot verify launched FENYVO process'
    }

    if (-not [string]::Equals(
        [IO.Path]::GetFullPath($actual.Path),
        [IO.Path]::GetFullPath($exe),
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Launched process path mismatch'
    }

    if ($RequireFlutterReady) {
        if (-not $confirmed) {
            throw 'Flutter readiness signal was not received'
        }

        Write-Host 'FLUTTER FIRST FRAME VERIFIED' -ForegroundColor Green
    }

    $launchVerified = $true
    Write-Host "FENYVO LAUNCH VERIFIED: PID $expectedPid" -ForegroundColor Green
}
finally {
    if ($null -eq $previousReadyToken) {
        Remove-Item Env:FENYVO_UPDATE_TOKEN -ErrorAction SilentlyContinue
    }
    else {
        $env:FENYVO_UPDATE_TOKEN = $previousReadyToken
    }

    if ($null -eq $previousReadyFile) {
        Remove-Item Env:FENYVO_UPDATE_READY_FILE -ErrorAction SilentlyContinue
    }
    else {
        $env:FENYVO_UPDATE_READY_FILE = $previousReadyFile
    }

    if ($null -ne $readyFile -and
        [IO.File]::Exists($readyFile)) {
        Remove-Item -LiteralPath $readyFile -Force
    }

    if ($null -ne $process) {
        try {
            $process.Refresh()

            if (-not $process.HasExited) {
                if (-not $launchVerified) {
                    $process.Kill()

                    if (-not $process.WaitForExit(10000)) {
                        throw 'Failed to terminate unsuccessful launch'
                    }
                }
            }
        }
        finally {
            $process.Dispose()
        }
    }
}
