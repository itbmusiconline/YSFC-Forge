# embedded\build-embedded-embedcss.ps1
# Run this from the embedded folder. It finds the latest
# ysfc_forge_library_builder_v*.html in the parent folder,
# extracts the first <style> and <body>, and writes a single
# ysfc-library-builder.html that injects the CSS via <script> (no external CSS).
# All file IO uses UTF-8. Existing outputs are backed up with timestamp.

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

# Targets
$htmlTarget = Join-Path $PSScriptRoot "ysfc-library-builder.html"

# Backup existing files with date.time format
$timestamp = Get-Date -Format "yyyyMMdd.HHmmss"
if (Test-Path $htmlTarget) {
    $backupName = "ysfc-library-builder.$timestamp.html"
    Rename-Item -Path $htmlTarget -NewName $backupName
    Write-Host "Backed up existing $htmlTarget -> $backupName"
}

# Read source as UTF-8
$encoding = [System.Text.Encoding]::UTF8
try {
    $html = [System.IO.File]::ReadAllText($sourcePath, $encoding)
} catch {
    Write-Error "Failed to read source file: $sourcePath"
    exit 1
}

# Extract first <style>...</style> (case-insensitive, single-line)
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

# Build final HTML:
# - embed raw CSS inside a <script type="text/plain"> to avoid escaping issues
# - then a small script reads that text and injects it as a <style> element
# - then append the body content
$embeddedHtml = @"
<!-- Auto-generated embedded version (CSS injected via script) -->

<!-- Raw CSS stored in a non-executing script tag to preserve exact characters -->
<script id="ysfc-raw-css" type="text/plain">
$styleContent
</script>

<script>
(function(){
    const raw = document.getElementById('ysfc-raw-css');
    if (!raw) return;
    const css = raw.textContent || raw.innerText || '';
    const style = document.createElement('style');
    style.type = 'text/css';
    style.textContent = css;
    document.head.appendChild(style);
    // optional: remove the raw script tag to keep DOM clean
    // raw.parentNode.removeChild(raw);
})();
</script>

<!-- Place the whole <body> content below -->
$bodyContent
"@

# Write output as UTF-8
try {
    [System.IO.File]::WriteAllText($htmlTarget, $embeddedHtml, $encoding)
} catch {
    Write-Error "Failed to write HTML file: $htmlTarget"
    exit 1
}

Write-Host "Source: $sourcePath"
Write-Host "Generated: $htmlTarget"
