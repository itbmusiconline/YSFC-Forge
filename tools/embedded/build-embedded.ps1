# embedded\build-embedded.ps1
# Run from the embedded folder

# Ensure script runs relative to its folder
Set-Location $PSScriptRoot

# Find latest source HTML in parent folder
$sourceFile = Get-ChildItem .. -Filter "ysfc_forge_library_builder_v*.html" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $sourceFile) {
    Write-Error "No ysfc_forge_library_builder_v*.html found in parent folder."
    exit 1
}

$sourcePath = $sourceFile.FullName

# Targets (in this folder)
$cssTarget  = Join-Path $PSScriptRoot "ysfc-library-builder-style.css"
$htmlTarget = Join-Path $PSScriptRoot "ysfc-library-builder-body.html"

# Backup existing files with date.time format
$timestamp = Get-Date -Format "yyyyMMdd.HHmmss"
if (Test-Path $cssTarget)  { Rename-Item -Path $cssTarget  -NewName ("ysfc-library-builder-style.$timestamp.css") }
if (Test-Path $htmlTarget) { Rename-Item -Path $htmlTarget -NewName ("ysfc-library-builder-body.$timestamp.html") }

# Read source as UTF-8
$encoding = [System.Text.Encoding]::UTF8
try {
    $html = [System.IO.File]::ReadAllText($sourcePath, $encoding)
} catch {
    Write-Error "Failed to read source file: $sourcePath"
    exit 1
}

# Extract first <style>...</style>
$styleMatch = [regex]::Match($html, "(?is)<style\b[^>]*>(.*?)</style>")
if (-not $styleMatch.Success) {
    Write-Error "No <style> block found in source file."
    exit 1
}
$styleContent = $styleMatch.Groups[1].Value.Trim("`r","`n")

# Extract first <body>...</body>
$bodyMatch = [regex]::Match($html, "(?is)<body\b[^>]*>(.*?)</body>")
if (-not $bodyMatch.Success) {
    Write-Error "No <body> block found in source file."
    exit 1
}
$bodyContent = $bodyMatch.Groups[1].Value.Trim("`r","`n")

# Write CSS file (UTF-8)
try {
    [System.IO.File]::WriteAllText($cssTarget, $styleContent, $encoding)
} catch {
    Write-Error "Failed to write CSS file: $cssTarget"
    exit 1
}

# Build HTML that loads external CSS then appends body content
$loader = @"
<!-- SPDX-License-Identifier: MIT
YSFC Forge Library Builder
Copyright (c) 2026 Johan Adolfsson
Licensed under the MIT License
See: https://github.com/YSFCforge/ysfc-forge/blob/main/LICENSE
-->

<!-- Loading the separate CSS file -->
<script>
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = './ysfc-library-builder-style.css'; // Put the correct URL of the CSS file here
    document.head.appendChild(link);
</script>

<!-- Place the whole <body> content below -->
"@

$finalHtml = $loader + "`r`n" + $bodyContent

# Write HTML file (UTF-8)
try {
    [System.IO.File]::WriteAllText($htmlTarget, $finalHtml, $encoding)
} catch {
    Write-Error "Failed to write HTML file: $htmlTarget"
    exit 1
}

Write-Host "Source: $sourcePath"
Write-Host "Generated: $cssTarget"
Write-Host "Generated: $htmlTarget"
