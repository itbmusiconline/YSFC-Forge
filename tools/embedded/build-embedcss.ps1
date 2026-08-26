# embedded\build-embedded-embedcss.ps1
# Run this from the embedded folder. It finds the latest
# ysfc_forge_library_builder_v*.html in the parent folder,
# applies itb-custom patches (default language, default view, heading),
# extracts the (patched) <style> and <body>, and writes a single
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

# -- itb-custom patches (applied to $html before extraction) --------------

# 1) Force default language to English. Upstream defaults to Swedish when
#    no 'ysfc-lang' value is in localStorage yet (first-time visitors).
$langPattern = "localStorage\.getItem\('ysfc-lang'\)\s*\|\|\s*'sv'"
if ($html -match $langPattern) {
    $html = $html -replace $langPattern, "localStorage.getItem('ysfc-lang') || 'en'"
    Write-Host "itb-custom: default language patched to English."
} else {
    Write-Warning "itb-custom: could not find the Swedish-default language line to patch. Upstream may have changed this - check manually."
}

# 2) Sanity-check (not a patch): upstream already defaults to Simple View
#    (initialAdvanced = false) unless a visitor's browser has 'ysfc-advanced'
#    set to 'true' in localStorage. Warn if upstream ever changes this default.
if ($html -notmatch "let initialAdvanced = false;") {
    Write-Warning "itb-custom: expected Simple-View default not found (looked for: let initialAdvanced = false;). Upstream may have changed this - verify the embedded page opens in Simple View."
} else {
    Write-Host "itb-custom: confirmed default view is still Simple View."
}

# 3) Convert the top <h1>YSFC Forge Library Builder ...</h1> heading into
#    <h3>, with "YSFC Forge" linked to the GitHub org. Everything after
#    "Library Builder" (version span, separator, buttons, etc.) is kept
#    exactly as upstream ships it.
$h1Pattern = '(?s)<h1>\s*YSFC Forge Library Builder(?<rest>.*?)</h1>'
$h1Match = [regex]::Match($html, $h1Pattern)
if (-not $h1Match.Success) {
    Write-Warning "itb-custom: could not find the expected <h1>YSFC Forge Library Builder...</h1> block. Skipping heading customization - upstream markup may have changed."
} else {
    $restOfHeading = $h1Match.Groups['rest'].Value
    $newHeading = @"
<h3>
  <a href="https://github.com/YSFCforge/" class="ver" title="Open the YSFC Forge project on GitHub" target="_blank" rel="noopener noreferrer">YSFC Forge</a> Library Builder$restOfHeading</h3>
"@
    $html = $html.Substring(0, $h1Match.Index) + $newHeading + $html.Substring($h1Match.Index + $h1Match.Length)
    Write-Host "itb-custom: heading converted from h1 to linked h3."
}

# ---------------------------------------------------------------------------

# Extract first <style>...</style> (case-insensitive, single-line)
$styleMatch = [regex]::Match($html, "(?is)<style\b[^>]*>(.*?)</style>")
if (-not $styleMatch.Success) {
    Write-Error "No <style> block found in source file."
    exit 1
}
$styleContent = $styleMatch.Groups[1].Value.Trim("`r","`n")

# itb-custom: upstream styles the whole header through h1-scoped rules
# (h1, h1 .ver, h1 .sep, h1 .spacer, h1 .btn-group). Now that the heading
# is an <h3>, none of them match any more - which drops "display: flex"
# and ".spacer { flex: 1 }" and so breaks the right-alignment of the
# button group. Mirror every h1-scoped rule onto h3 rather than listing
# them by hand, so any h1 rule upstream adds later is carried over too.
$h1RulePattern = '(?m)^[ \t]*h1\b(?<sel>[^{}]*)\{(?<body>[^{}]*)\}'
$h1Rules = [regex]::Matches($styleContent, $h1RulePattern)
if ($h1Rules.Count -eq 0) {
    Write-Warning "itb-custom: found no h1-scoped CSS rules to mirror onto h3. The embedded header will lose its layout - check upstream's CSS."
} else {
    $mirrored = "`r`n/* itb-custom: h1 rules mirrored onto h3 (heading downgraded for embedding) */`r`n"
    foreach ($rule in $h1Rules) {
        $mirrored += "h3" + $rule.Groups['sel'].Value + "{" + $rule.Groups['body'].Value + "}`r`n"
    }
    $styleContent += $mirrored
    Write-Host ("itb-custom: mirrored {0} h1 CSS rule(s) onto h3." -f $h1Rules.Count)
}

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
<!-- SPDX-License-Identifier: MIT
YSFC Forge Library Builder
Copyright (c) 2026 Johan Adolfsson
Licensed under the MIT License
See: https://github.com/YSFCforge/ysfc-forge/blob/main/LICENSE
-->

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
