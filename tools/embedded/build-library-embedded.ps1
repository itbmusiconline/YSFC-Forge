# embedded\build-library-embedded.ps1
# Run this from the embedded folder. It finds the latest
# ysfc_forge_library_builder_v*.html in the parent folder, applies the
# itb-custom patches, and splits it into TWO files:
#
#   ysfc-library-builder-embed.html - paste into the Elementor HTML widget
#                                     (licence header + CSS + markup + script tag)
#   ysfc-library-builder.js         - upload to the web server, see $JsBaseUrl
#
# The CSS stays INLINE in the widget and is injected before the markup, so
# there is no flash of unstyled content. Only the JavaScript is externalised.
# All file IO uses UTF-8. Existing outputs are backed up with timestamp.
#
# This supersedes build-embedded.ps1, which split the CSS out into its own
# file and therefore produced an unstyled -body.html.

# --- Configuration ---------------------------------------------------------
# Where the .js file will live on the web server. Change this one line if you
# move it. This is a ROOT-RELATIVE path: the leading "/" makes it resolve from
# the site root regardless of which page the widget sits on. If WordPress is
# installed in a subdirectory, include it here (e.g. "/shop/wp-content/...").
$JsBaseUrl = "/wp-content/uploads/ysfc-forge"

# How many timestamped backups to keep per output file. Older ones are
# deleted automatically at the end of each run. Set to 0 to keep none, or to
# a large number to effectively disable the cleanup.
$BackupsToKeep = 5
# ---------------------------------------------------------------------------

Set-Location $PSScriptRoot

# Deletes all but the newest $Keep backups matching a regex. The regex is
# deliberately strict - it matches only "name.YYYYMMDD.HHMMSS.ext" - so a
# current output file can never be caught by the cleanup.
function Remove-OldBackups {
    param([string]$Pattern, [int]$Keep)
    $old = Get-ChildItem -Path $PSScriptRoot -File |
           Where-Object { $_.Name -match $Pattern } |
           Sort-Object LastWriteTime -Descending |
           Select-Object -Skip $Keep
    foreach ($f in $old) {
        Remove-Item -LiteralPath $f.FullName -Force
        Write-Host "  Removed old backup: $($f.Name)"
    }
    return @($old).Count
}

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
$htmlTarget = Join-Path $PSScriptRoot "ysfc-library-builder-embed.html"
$jsTarget   = Join-Path $PSScriptRoot "ysfc-library-builder.js"

# Read source as UTF-8. ReadAllText strips a leading BOM automatically.
$encoding = [System.Text.Encoding]::UTF8

# Write outputs as UTF-8 WITHOUT a BOM. A BOM at the start of the fragment
# survives into the page as a stray U+FEFF text node inside .forge-app, which
# WordPress's wpautop can turn into an empty <p>. The .ps1 scripts themselves
# keep their BOM - Windows PowerShell 5.1 needs it.
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
Write-Host ("itb-custom: JavaScript split out ({0:N0} bytes) - CSS and markup kept inline ({1:N0} bytes)." -f $jsContent.Length, ($styleContent.Length + $markup.Length))

# -- itb-custom patch 1 (JS): default language ------------------------------
# Upstream defaults to Swedish for first-time visitors. The language toggle
# button and any saved visitor preference are deliberately left working.
$langPattern = "localStorage\.getItem\('ysfc-lang'\)\s*\|\|\s*'sv'"
if ($jsContent -match $langPattern) {
    $jsContent = $jsContent -replace $langPattern, "localStorage.getItem('ysfc-lang') || 'en'"
    Write-Host "itb-custom: default language patched to English."
} else {
    Write-Warning "itb-custom: could not find the Swedish-default language line to patch. Upstream may have changed this - check manually."
}

# -- itb-custom patch 2 (JS): Simple View default is a check, not a patch ---
if ($jsContent -notmatch "let initialAdvanced = false;") {
    Write-Warning "itb-custom: expected Simple-View default not found (looked for: let initialAdvanced = false;). Upstream may have changed this - verify the embedded page opens in Simple View."
} else {
    Write-Host "itb-custom: confirmed default view is still Simple View."
}

# -- itb-custom patch 3 (markup): <h1> becomes a linked <h3> ----------------
$h1Pattern = '(?s)<h1>\s*YSFC Forge Library Builder(?<rest>.*?)</h1>'
$h1Match = [regex]::Match($markup, $h1Pattern)
if (-not $h1Match.Success) {
    Write-Warning "itb-custom: could not find the expected <h1>YSFC Forge Library Builder...</h1> block. Skipping heading customization - upstream markup may have changed."
} else {
    $restOfHeading = $h1Match.Groups['rest'].Value
    $newHeading = @"
<h3>
  <a href="https://github.com/YSFCforge/" class="ver" title="Open the YSFC Forge project on GitHub" target="_blank" rel="noopener noreferrer">YSFC Forge</a> Library Builder$restOfHeading</h3>
"@
    $markup = $markup.Substring(0, $h1Match.Index) + $newHeading + $markup.Substring($h1Match.Index + $h1Match.Length)
    Write-Host "itb-custom: heading converted from h1 to linked h3."
}

# -- itb-custom patch 4 (CSS): .seltable-wrap height ------------------------
$selPattern = '(?s)(\.seltable-wrap\s*\{[^}]*?height:\s*)251px'
if ($styleContent -match $selPattern) {
    $styleContent = $styleContent -replace $selPattern, '${1}259px'
    Write-Host "itb-custom: .seltable-wrap height patched 251px -> 259px."
} else {
    Write-Warning "itb-custom: could not find '.seltable-wrap { ... height: 251px }' to patch. Upstream may have changed it - check the selection table height."
}

# -- itb-custom patch 5 (CSS): re-scope body onto .forge-app ----------------
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

# -- itb-custom patch 6 (CSS): mirror every h1-scoped rule onto h3 ----------
# Required by patch 3: upstream styles the header through h1-scoped rules, and
# none of them match once the heading is an <h3>. Mirroring rather than
# hand-listing means any h1 rule upstream adds later is carried over too.
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

# -- Build the widget fragment ----------------------------------------------
$jsUrl = ($JsBaseUrl.TrimEnd('/')) + "/ysfc-library-builder.js"

$embeddedHtml = @"
<!-- SPDX-License-Identifier: MIT

YSFC Forge Library Builder
Original work: Copyright (c) 2026 Johan Adolfsson
Modifications: Copyright (c) 2026 Kalin Mirchev, ITB Music Online
  English default, linked h3 heading, embeddable fragment with external JS.
  Functionality unchanged.

Licensed under the MIT License
See: https://github.com/YSFCforge/ysfc-forge/blob/main/LICENSE
-->

<!-- Auto-generated embedded version (CSS injected via script) -->
<!-- Raw CSS stored in a non-executing script tag to preserve exact characters -->
<script id="ysfc-lib-raw-css" type="text/plain">
$styleContent
</script>

<script>
(function(){
    const raw = document.getElementById('ysfc-lib-raw-css');
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

<!-- The application code expects the markup above to already exist, so this
     tag must stay LAST and must NOT be given defer or async. Exclude this
     file from any JS optimisation/deferral plugin. -->
<script src="$jsUrl"></script>
"@

# -- Compare against the previous export ------------------------------------
$htmlChanged = ($null -eq $prevHtml) -or ($prevHtml -ne $embeddedHtml)
$jsChanged   = ($null -eq $prevJs)   -or ($prevJs   -ne $jsContent)
$firstRun    = ($null -eq $prevHtml) -and ($null -eq $prevJs)

# Back up the previous export, but only the files that are actually changing.
$timestamp = Get-Date -Format "yyyyMMdd.HHmmss"
if ($htmlChanged -and (Test-Path $htmlTarget)) {
    Rename-Item -Path $htmlTarget -NewName "ysfc-library-builder-embed.$timestamp.html"
    Write-Host "Backed up previous ysfc-library-builder-embed.html -> ysfc-library-builder-embed.$timestamp.html"
}
if ($jsChanged -and (Test-Path $jsTarget)) {
    Rename-Item -Path $jsTarget -NewName "ysfc-library-builder.$timestamp.js"
    Write-Host "Backed up previous ysfc-library-builder.js -> ysfc-library-builder.$timestamp.js"
}

# Write outputs as UTF-8 (no BOM)
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
        Write-Host "  Widget HTML : CHANGED   -> re-paste ysfc-library-builder-embed.html into Elementor"
    } else {
        Write-Host "  Widget HTML : unchanged -> nothing to do in Elementor"
    }
    if ($jsChanged) {
        Write-Host "  JavaScript  : CHANGED   -> re-upload ysfc-library-builder.js to $JsBaseUrl"
        Write-Host "                             (purge the CDN/cache afterwards if you use one)"
    } else {
        Write-Host "  JavaScript  : unchanged -> no need to re-upload"
    }
    if (-not $htmlChanged -and -not $jsChanged) {
        Write-Host ""
        Write-Host "  Nothing changed - the site is already up to date."
    }
}

# -- Backup retention -------------------------------------------------------
$removed = 0
$removed += Remove-OldBackups -Pattern '^ysfc-library-builder-embed\.\d{8}\.\d{6}\.html$' -Keep $BackupsToKeep
$removed += Remove-OldBackups -Pattern '^ysfc-library-builder\.\d{8}\.\d{6}\.js$'         -Keep $BackupsToKeep
if ($removed -gt 0) {
    Write-Host ""
    Write-Host ("Backup cleanup: removed {0} old backup(s), keeping the newest {1} of each." -f $removed, $BackupsToKeep)
}

Write-Host ""
Write-Host "Reminder: the widget's container must carry the CSS class .forge-app"
