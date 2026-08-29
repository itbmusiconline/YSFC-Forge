# embedded\build-embedded.ps1
# Run from the embedded folder.
# Applies itb-custom patches (default language, default view, heading) to the
# latest upstream source before splitting it into a separate CSS file and body HTML.

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

# Extract first <style>...</style>
$styleMatch = [regex]::Match($html, "(?is)<style\b[^>]*>(.*?)</style>")
if (-not $styleMatch.Success) {
    Write-Error "No <style> block found in source file."
    exit 1
}
$styleContent = $styleMatch.Groups[1].Value.Trim("`r","`n")

# itb-custom: the selection table is 8px taller here than upstream ships it,
# to line up with the surrounding layout on the host page. Anchored on the
# rule name as well as the value so it cannot drift onto another rule.
$selPattern = '(?s)(\.seltable-wrap\s*\{[^}]*?height:\s*)251px'
if ($styleContent -match $selPattern) {
    $styleContent = $styleContent -replace $selPattern, '${1}259px'
    Write-Host "itb-custom: .seltable-wrap height patched 251px -> 259px."
} else {
    Write-Warning "itb-custom: could not find '.seltable-wrap { ... height: 251px }' to patch. Upstream may have changed it - check the selection table height."
}

# itb-custom: the host page loads this fragment into a container carrying
# the .forge-app class, so upstream's body-level styling (font, colours,
# background, padding) has to be re-scoped onto that container instead of
# the hosting page's own <body>. Skips the patch unless exactly one body
# rule is present, so an upstream change cannot cause a silent mis-edit.
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
Original work: Copyright (c) 2026 Johan Adolfsson
Modifications: Copyright (c) 2026 Kalin Mirchev, ITB Music Online
  English default, linked h3 heading, embeddable fragment. Functionality unchanged.

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
