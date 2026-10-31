param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $ProjectRoot 'lib\services\app_language_service.dart'
if (!(Test-Path -LiteralPath $source)) {
    throw 'LOCALIZATION SOURCE NOT FOUND'
}

$lines = [IO.File]::ReadAllLines($source)
$langs = @('ru', 'uk', 'en')
$data = @{}

foreach ($lang in $langs) {
    $data[$lang] = @{}
}

$sectionPattern = '^\s{4}[''"](ru|uk|en)[''"]\s*:\s*\{'
$keyPattern = '^\s{6}[''"]([A-Za-z][A-Za-z0-9_]*)[''"]\s*:'
$placeholderPattern = '(?<!\{)\{[A-Za-z_][A-Za-z0-9_]*\}(?!\})'

$currentLang = $null
$currentKey = $null
$valueLines = New-Object System.Collections.Generic.List[string]

function SaveEntry {
    if ($null -eq $currentLang -or $null -eq $currentKey) {
        return
    }

    if ($data[$currentLang].ContainsKey($currentKey)) {
        throw "DUPLICATE KEY: $currentLang / $currentKey"
    }

    $value = $valueLines -join "`n"
    $placeholders = @(
        [regex]::Matches($value, $placeholderPattern) |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
    )

    $data[$currentLang][$currentKey] = $placeholders
}

$sections = @{}

foreach ($line in $lines) {
    if ($line -match $sectionPattern) {
        SaveEntry
        $currentLang = $Matches[1]
        if ($sections.ContainsKey($currentLang)) {
            throw "DUPLICATE LANGUAGE SECTION: $currentLang"
        }
        $sections[$currentLang] = $true
        $currentKey = $null
        $valueLines.Clear()
        continue
    }

    if ($null -eq $currentLang) {
        continue
    }

    if ($line -match '^\s{4}\},?\s*$') {
        SaveEntry
        $currentLang = $null
        $currentKey = $null
        $valueLines.Clear()
        continue
    }

    if ($line -match $keyPattern) {
        SaveEntry
        $currentKey = $Matches[1]
        $valueLines.Clear()
        $valueLines.Add($line)
    }
    elseif ($null -ne $currentKey) {
        $valueLines.Add($line)
    }
}

SaveEntry

foreach ($lang in $langs) {
    if (!$sections.ContainsKey($lang)) {
        throw "LANGUAGE MISSING: $lang"
    }
}

$allKeys = @(
    foreach ($lang in $langs) {
        $data[$lang].Keys
    }
) | Sort-Object -Unique

$errorsFound = 0
$parameterKeys = 0

foreach ($lang in $langs) {
    Write-Host ("LANGUAGE {0}: {1} KEYS" -f $lang, $data[$lang].Count)

    foreach ($key in $allKeys) {
        if (!$data[$lang].ContainsKey($key)) {
            Write-Host "MISSING: $lang / $key" -ForegroundColor Red
            $errorsFound++
        }
    }
}

foreach ($key in $allKeys) {
    $signatures = @()
    $hasParameters = $false

    foreach ($lang in $langs) {
        if (!$data[$lang].ContainsKey($key)) {
            continue
        }

        $parameters = @($data[$lang][$key])
        if ($parameters.Count -gt 0) {
            $hasParameters = $true
        }
        $signatures += ($parameters -join ',')
    }

    if ($hasParameters) {
        $parameterKeys++
    }

    if (@($signatures | Sort-Object -Unique).Count -gt 1) {
        Write-Host "PLACEHOLDER MISMATCH: $key" -ForegroundColor Red
        $errorsFound++
    }
}

Write-Host "TOTAL UNIQUE KEYS: $($allKeys.Count)"
Write-Host "KEYS WITH PLACEHOLDERS: $parameterKeys"
Write-Host "ERRORS: $errorsFound"

if ($errorsFound -gt 0) {
    throw 'LOCALIZATION GUARD FAILED'
}

Write-Host '=== LOCALIZATION GUARD PASSED ===' -ForegroundColor Green