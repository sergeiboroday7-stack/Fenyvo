param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [IO.Path]::GetFullPath($ArchivePath)
$destination = [IO.Path]::GetFullPath($DestinationPath)

if (-not [IO.File]::Exists($archive)) {
    throw 'Update archive does not exist'
}

if ([IO.Directory]::Exists($destination) -or
    [IO.File]::Exists($destination)) {
    throw 'Destination must not already exist'
}

$parent = [IO.Path]::GetDirectoryName($destination)

if (-not [IO.Directory]::Exists($parent)) {
    throw 'Destination parent directory does not exist'
}

$maxUncompressed = 1024L * 1024L * 1024L
$maxEntries = 10000
$totalBytes = 0L
$paths = New-Object 'System.Collections.Generic.HashSet[string]' (
    [StringComparer]::OrdinalIgnoreCase
)

$zip = [IO.Compression.ZipFile]::OpenRead($archive)

try {
    if ($zip.Entries.Count -gt $maxEntries) {
        throw 'Too many ZIP entries'
    }

    $root = $destination.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar

    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('/', '\')

        if ([string]::IsNullOrWhiteSpace($name) -or
            $name.StartsWith('\') -or
            $name.Contains(':')) {
            throw "Invalid ZIP entry: $name"
        }

        $parts = $name.TrimEnd('\').Split('\')

        foreach ($part in $parts) {
            if ([string]::IsNullOrWhiteSpace($part) -or
                $part -eq '.' -or
                $part -eq '..' -or
                $part.EndsWith('.') -or
                $part.EndsWith(' ') -or
                $part -match '[<>:"|?*\x00-\x1F]' -or
                $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') {
                throw "Unsafe Windows ZIP name: $name"
            }
        }

        $target = [IO.Path]::GetFullPath(
            [IO.Path]::Combine($destination, $name)
        )

        if (-not $target.StartsWith(
            $root,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "ZIP path traversal rejected: $name"
        }

        if (-not $paths.Add($target)) {
            throw "Duplicate ZIP entry: $name"
        }

        # Reject Unix symbolic links.
        $unixMode = ($entry.ExternalAttributes -shr 16) -band 0xF000

        if ($unixMode -eq 0xA000) {
            throw "Symbolic link rejected: $name"
        }

        $totalBytes += $entry.Length

        if ($totalBytes -gt $maxUncompressed) {
            throw 'Uncompressed update exceeds 1 GiB'
        }
    }

    # Check file/directory collisions before extraction.
    $filePaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('/', '\')

        if (-not $name.EndsWith('\')) {
            $target = [IO.Path]::GetFullPath(
                [IO.Path]::Combine($destination, $name)
            )

            [void]$filePaths.Add($target)
        }
    }

    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('/', '\')
        $target = [IO.Path]::GetFullPath(
            [IO.Path]::Combine($destination, $name)
        )

        if ($name.EndsWith('\')) {
            if ($filePaths.Contains($target)) {
                throw "File/directory conflict: $name"
            }
        }

        $relative = $target.Substring($root.Length).TrimEnd('\')
        $segments = $relative.Split('\')
        $current = $destination

        for ($i = 0; $i -lt $segments.Length - 1; $i++) {
            $current = [IO.Path]::Combine($current, $segments[$i])

            if ($filePaths.Contains($current)) {
                throw "File/directory conflict: $name"
            }
        }
    }
}
finally {
    $zip.Dispose()
}

[IO.Directory]::CreateDirectory($destination) | Out-Null

try {
    [IO.Compression.ZipFile]::ExtractToDirectory(
        $archive,
        $destination
    )

    $exe = Join-Path $destination 'fenyvo.exe'

    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw 'fenyvo.exe missing from update archive'
    }

    Write-Host 'UPDATE EXTRACTION VERIFIED' -ForegroundColor Green
}
catch {
    if ([IO.Directory]::Exists($destination)) {
        [IO.Directory]::Delete($destination, $true)
    }

    throw
}
