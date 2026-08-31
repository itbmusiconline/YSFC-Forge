# embedded\build-sysex-embedded.ps1
# Run this from the embedded folder. It finds the latest
# ysfc_forge_sysex_converter_v*.html in the parent folder, applies the
# itb-custom patches, and splits it into TWO files:
#
#   ysfc-sysex-converter.html  - paste into the Elementor HTML widget
#                                (licence header + CSS + markup + script tag)
#   ysfc-sysex-converter.js    - upload to the web server, see $JsBaseUrl
#
# The converter is ~2.3 MB, of which ~2.26 MB is JavaScript, so the script
# is kept out of the page and served as a cacheable static file instead.
# All file IO uses UTF-8. Existing outputs are backed up with timestamp.

# --- Configuration ---------------------------------------------------------
# Where the .js file will live on the web server. Change this one line if you
# move it. No trailing slash needed; the filename is appended automatically.
$JsBaseUrl = "/wp-content/uploads/ysfc-forge"
# ---------------------------------------------------------------------------

Set-Location $PSScriptRoot

# Find latest source HTML in parent folder
$sourceFile = Get-ChildItem .. -Filter "ysfc_forge_sysex_converter_v*.html" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $sourceFile) {
    Write-Error "No ysfc_forge_sysex_converter_v*.html found in parent folder."
    exit 1
}

$sourcePath = $sourceFile.FullName

# Targets
$htmlTarget = Join-Path $PSScriptRoot "ysfc-sysex-converter.html"
$jsTarget   = Join-Path $PSScriptRoot "ysfc-sysex-converter.js"

# Read source as UTF-8. ReadAllText strips a leading BOM automatically.
$encoding = [System.Text.Encoding]::UTF8

# Write outputs as UTF-8 WITHOUT a BOM. A BOM at the start of the fragment
# survives into the page as a stray U+FEFF text node inside .forge-app, which
# WordPress's wpautop can turn into an empty <p>. A BOM on the .js is likewise
# unnecessary. The .ps1 scripts themselves keep their BOM - Windows
# PowerShell 5.1 needs it - but the generated files must not have one.
$outEncoding = New-Object System.Text.UTF8Encoding $false

# Capture the PREVIOUS export before anything is overwritten, so the run can
# report which of the two files actually changed. That decides whether the
# Elementor widget needs re-pasting or only the .js needs re-uploading.
$prevHtml = $null
$prevJs   = $null
if (Test-Path $htmlTarget) { $prevHtml = [System.IO.File]::ReadAllText($htmlTarget, $encoding) }
if (Test-Path $jsTarget)   { $prevJs   = [System.IO.File]::ReadAllText($jsTarget,   $encoding) }
try {
    $html = [System.IO.File]::ReadAllText($sourcePath, $encoding)
} catch {
    Write-Error "Failed to read source file: $sourcePath"
    exit 1
}

# -- Extract <style> --------------------------------------------------------
$styleMatch = [regex]::Match($html, "(?is)<style\b[^>]*>(.*?)</style>")
if (-not $styleMatch.Success) {
    Write-Error "No <style> block found in source file."
    exit 1
}
$styleContent = $styleMatch.Groups[1].Value.Trim("`r","`n")

# -- Extract <body> ---------------------------------------------------------
$bodyMatch = [regex]::Match($html, "(?is)<body\b[^>]*>(.*?)</body>")
if (-not $bodyMatch.Success) {
    Write-Error "No <body> block found in source file."
    exit 1
}
$bodyContent = $bodyMatch.Groups[1].Value.Trim("`r","`n")

# -- Split the single inline <script> out of the body -----------------------
# The converter carries exactly one script block. Everything before it is
# markup; the block's contents become the external .js file.
$scriptMatch = [regex]::Match($bodyContent, "(?is)<script\b[^>]*>(.*?)</script>")
if (-not $scriptMatch.Success) {
    Write-Error "No <script> block found inside <body>. Cannot split the JavaScript out."
    exit 1
}
$scriptCount = ([regex]::Matches($bodyContent, "(?is)<script\b[^>]*>")).Count
if ($scriptCount -ne 1) {
    Write-Warning "itb-custom: expected exactly 1 script block in the body but found $scriptCount. Only the first is being externalised - check the generated files."
}
$jsContent = $scriptMatch.Groups[1].Value.Trim("`r","`n")
$markup = ($bodyContent.Remove($scriptMatch.Index, $scriptMatch.Length)).Trim("`r","`n")
Write-Host ("itb-custom: JavaScript split out ({0:N0} bytes) - markup kept inline ({1:N0} bytes)." -f $jsContent.Length, $markup.Length)

# -- itb-custom patch 1: default language -----------------------------------
# Upstream defaults to Swedish for first-time visitors. The language toggle
# button and any saved visitor preference are deliberately left working.
$langPattern = "localStorage\.getItem\('ysfc-lang'\)\s*\|\|\s*'sv'"
if ($jsContent -match $langPattern) {
    $jsContent = $jsContent -replace $langPattern, "localStorage.getItem('ysfc-lang')||'en'"
    Write-Host "itb-custom: default language patched to English."
} else {
    Write-Warning "itb-custom: could not find the Swedish-default language line to patch. Upstream may have changed this - check manually."
}

# -- itb-custom patch 2: re-scope body styling onto .forge-app --------------
# The host page loads this fragment into a container carrying the .forge-app
# class. Upstream's body rule would otherwise override the hosting page's own
# body styling. This stylesheet is minified, so the rule is "body{...}" with
# no space. Anchored to start-of-line, which also keeps it off "tbody".
$bodyRulePattern = '(?m)^(?<indent>[ \t]*)body\s*\{'
$bodyRuleCount = ([regex]::Matches($styleContent, $bodyRulePattern)).Count
if ($bodyRuleCount -eq 1) {
    $styleContent = $styleContent -replace $bodyRulePattern, '${indent}.forge-app {'
    Write-Host "itb-custom: body selector re-scoped to .forge-app."
} elseif ($bodyRuleCount -eq 0) {
    Write-Warning "itb-custom: no 'body { ... }' rule found to re-scope to .forge-app. Upstream may have changed it - check the embed's font, colours and padding."
} else {
    Write-Warning "itb-custom: found $bodyRuleCount 'body { ... }' rules but expected exactly 1. Skipping the .forge-app re-scope to avoid an unintended edit - check upstream's CSS."
}

# -- itb-custom patch 3: link "YSFC Forge" in the header to GitHub ----------
# The heading is a <div class="brand">, not an <h1>, so nothing is re-scoped
# here. The link uses class="ver", which .brand .ver already colours with the
# accent, so no companion CSS rule is needed.
$brandPattern = '(?s)(<div class="brand">\s*)YSFC Forge SysEx Converter'
if ($markup -match $brandPattern) {
    $brandLink = '<a href="https://github.com/YSFCforge/" class="ver" title="Open the YSFC Forge project on GitHub" target="_blank" rel="noopener noreferrer">YSFC Forge</a> SysEx Converter'
    $markup = $markup -replace $brandPattern, ('${1}' + $brandLink)
    Write-Host "itb-custom: 'YSFC Forge' in the header linked to the GitHub project."
} else {
    Write-Warning "itb-custom: could not find the expected '<div class=`"brand`">YSFC Forge SysEx Converter' heading to link. Upstream markup may have changed."
}

# -- Build the widget fragment ----------------------------------------------
$jsUrl = ($JsBaseUrl.TrimEnd('/')) + "/ysfc-sysex-converter.js"

$embeddedHtml = @"
<!-- SPDX-License-Identifier: MIT

YSFC Forge SysEx Converter
Original work: Copyright (c) 2026 Johan Adolfsson
Modifications: Copyright (c) 2026 Kalin Mirchev, ITB Music Online
  English default, linked header, embeddable fragment with external JS.
  Functionality unchanged.

Licensed under the MIT License
See: https://github.com/YSFCforge/ysfc-forge/blob/main/LICENSE
-->

<!-- Auto-generated embedded version (CSS injected via script) -->
<!-- Raw CSS stored in a non-executing script tag to preserve exact characters -->
<script id="ysfc-sysex-raw-css" type="text/plain">
$styleContent
</script>

<script>
(function(){
    const raw = document.getElementById('ysfc-sysex-raw-css');
    if (!raw) return;
    const css = raw.textContent || raw.innerText || '';
    const style = document.createElement('style');
    style.type = 'text/css';
    style.textContent = css;
    document.head.appendChild(style);
})();
</script>

<!-- Markup -->
$markup

<!-- The application code runs immediately and expects the markup above to
     already exist, so this tag must stay LAST and must NOT be given defer
     or async. Exclude this file from any JS optimisation/deferral plugin. -->
<script src="$jsUrl"></script>
"@

# -- Compare against the previous export ------------------------------------
# Neither output contains a timestamp or any other volatile value, so a plain
# string comparison is a reliable "has this actually changed" test.
$htmlChanged = ($null -eq $prevHtml) -or ($prevHtml -ne $embeddedHtml)
$jsChanged   = ($null -eq $prevJs)   -or ($prevJs   -ne $jsContent)
$firstRun    = ($null -eq $prevHtml) -and ($null -eq $prevJs)

# Back up the previous export, but only the files that are actually changing.
$timestamp = Get-Date -Format "yyyyMMdd.HHmmss"
if ($htmlChanged -and (Test-Path $htmlTarget)) {
    Rename-Item -Path $htmlTarget -NewName "ysfc-sysex-converter.$timestamp.html"
    Write-Host "Backed up previous ysfc-sysex-converter.html -> ysfc-sysex-converter.$timestamp.html"
}
if ($jsChanged -and (Test-Path $jsTarget)) {
    Rename-Item -Path $jsTarget -NewName "ysfc-sysex-converter.$timestamp.js"
    Write-Host "Backed up previous ysfc-sysex-converter.js -> ysfc-sysex-converter.$timestamp.js"
}

# Write outputs as UTF-8
try {
    [System.IO.File]::WriteAllText($htmlTarget, $embeddedHtml, $outEncoding)
} catch {
    Write-Error "Failed to write HTML file: $htmlTarget"
    exit 1
}
try {
    [System.IO.File]::WriteAllText($jsTarget, $jsContent, $outEncoding)
} catch {
    Write-Error "Failed to write JS file: $jsTarget"
    exit 1
}

Write-Host ""
Write-Host "Source: $sourcePath"
Write-Host "Generated: $htmlTarget"
Write-Host "Generated: $jsTarget"

# -- What needs updating on the site ----------------------------------------
Write-Host ""
Write-Host "=== What changed since the last export ==="
if ($firstRun) {
    Write-Host "  No previous export found - this is the first run."
    Write-Host "  Upload the .js AND paste the .html; both are new."
} else {
    if ($htmlChanged) {
        Write-Host "  Widget HTML : CHANGED   -> re-paste ysfc-sysex-converter.html into Elementor"
    } else {
        Write-Host "  Widget HTML : unchanged -> nothing to do in Elementor"
    }
    if ($jsChanged) {
        Write-Host "  JavaScript  : CHANGED   -> re-upload ysfc-sysex-converter.js to $JsBaseUrl"
        Write-Host "                             (purge the CDN/cache afterwards if you use one)"
    } else {
        Write-Host "  JavaScript  : unchanged -> no need to re-upload"
    }
    if (-not $htmlChanged -and -not $jsChanged) {
        Write-Host ""
        Write-Host "  Nothing changed - the site is already up to date."
    }
}

Write-Host ""
Write-Host "Reminder: the widget's container must carry the CSS class .forge-app"
