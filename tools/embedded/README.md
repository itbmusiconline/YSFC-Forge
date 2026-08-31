# Embedded Tools for YSFC Forge Library Builder

## Purpose
This folder contains local PowerShell scripts used to generate embedded 
versions of the YSFC Forge Library Builder for use when the tool is not 
hosted directly, but in third party web builders, for example WordPress. 
These scripts are part of the `itb-custom` branch and are not included 
in the upstream project.

## Host page requirement: the `.forge-app` class

The generated output is an HTML **fragment**, not a complete page. It contains
no `<!DOCTYPE>`, `<html>`, `<head>` or `<body>` tags - the browser supplies
those, and inside WordPress the page already has them.

**The container that receives the output must carry the CSS class `.forge-app`.**

Upstream styles the whole app through a `body { ... }` rule. Left alone, that
rule overrides the host page's own body styling (font, colours, background,
padding). The build re-scopes it onto `.forge-app` so the styling applies only
inside the embed. If the container does not have that class, the embed will
render unstyled - wrong font, no background, no padding.

Set the class on the container that wraps the HTML widget, not on the widget's
inner markup. This is purely a styling boundary: no JavaScript depends on it,
and nothing else in the code was changed to accommodate it.

## Scripts
### build-embedcss.ps1
Generates:
- ysfc-library-builder.html  
(Extracts the content of <style> and <body> sections and combines them in a 
self-contained code that can be used within a HTML/JS compatible container. 
CSS is injected via <script>)

### build-library-embedded.ps1
Generates:
- ysfc-library-builder-embed.html  (paste into the Elementor HTML widget, ~44 KB)
- ysfc-library-builder.js          (upload to the web server, ~441 KB)

The recommended build. CSS and markup stay inline in the widget; only the
JavaScript is externalised, so the widget drops from ~495 KB to ~44 KB while
still rendering styled immediately.

*Replaced `build-embedded.ps1`*, which split the CSS out into its own file and
so produced a `-body.html` that rendered as unstyled plain text unless the
separate stylesheet happened to be loaded. That was not a flash-of-unstyled-
content problem and had nothing to do with external JavaScript - the file
simply contained no CSS at all.

### build-sysex-embedded.ps1
Generates:
- ysfc-sysex-converter.html  (paste into the Elementor HTML widget)
- ysfc-sysex-converter.js    (upload to the web server)

See "SysEx Converter: external JavaScript" below - this one works
differently from the two Library Builder scripts.

## SysEx Converter: external JavaScript

The SysEx Converter is about 2.3 MB, of which roughly 2.26 MB is a single
inline `<script>` block - over half of that is one base64 Y2L template
(`FMX_VERIFIED_11SLOT_Y2L_B64`). Pasting all of it into an Elementor widget
would store it in the WordPress database, re-send it uncached on every page
view, add a ~2.3 MB copy to every page revision, and slow the editor down.

So this script splits the tool in two:

| Part | Size | Where it goes |
|-|-|-|
| CSS + markup | ~22 KB | the Elementor HTML widget |
| JavaScript | ~2.26 MB | a static file on the server |

**Where to put the .js:** `/wp-content/uploads/ysfc-forge/`. The uploads
folder survives theme switches and theme, plugin and core updates, is already
writable, and is included in backup plugins by default. A dedicated subfolder
also makes it easy to write cache-plugin exclusion rules. Change `$JsBaseUrl`
at the top of the script if you move it.

Upload via FTP or the host's file manager - the WordPress Media Library
rejects `.js` by default, and that restriction should be left in place.

**Important - do not let any plugin defer this script.** The converter has no
`DOMContentLoaded` wrapper: it runs immediately and calls `applyLang();
render(); updateConvertGate();` at the end, so it depends on executing after
its markup is parsed. The generated `<script src>` tag is therefore placed
last and carries no `defer` or `async`. If an optimisation plugin (WP Rocket,
Autoptimize, LiteSpeed Cache) defers or moves it, the tool breaks. Exclude
`/wp-content/uploads/ysfc-forge/*` from JS optimisation.

The filename is fixed rather than version-stamped, so updating means replacing
one file and never re-pasting the widget. The trade-off is that cache
freshness relies on the server revalidating - **purge the CDN after each
update** if you use one.

### Knowing what to update

Each run compares the new output against the previous export and reports
which of the two files actually changed:

    === What changed since the last export ===
      Widget HTML : unchanged -> nothing to do in Elementor
      JavaScript  : CHANGED   -> re-upload ysfc-sysex-converter.js

Only the changed file is backed up. Note the comparison is on decoded text,
so a difference in file encoding alone would not be reported as a change.

### Customizations

Three of the six are applied here. The `h1`-to-`h3` conversion and the `h1`
CSS mirroring do not apply - the converter has no `<h1>`, its heading is a
`<div class="brand">` - and there is no `.seltable-wrap`.

1. **Default language set to English.** The converter's code is minified and
   uses a different variable, so this needs its own pattern:
   `let lang=localStorage.getItem('ysfc-lang')||'sv'`.
2. **`body` re-scoped to `.forge-app`.** Its stylesheet is minified, so the
   rule appears as `body{...}` with no space.
3. **"YSFC Forge" in the header linked to the GitHub project.** The link uses
   `class="ver"`, which `.brand .ver` already colours with the accent, so no
   companion CSS rule is needed here.

Unlike the Library Builder outputs, these two files are written **without a
UTF-8 BOM**. A BOM survives into the page as a stray U+FEFF text node inside
`.forge-app`, which WordPress's `wpautop` can turn into an empty `<p>`. The
`.ps1` scripts themselves keep their BOM - Windows PowerShell 5.1 needs it.

## Customizations applied at build time

**The tracked source file is never edited.** `ysfc_forge_library_builder_v*.html`
is kept byte-identical to upstream so every future sync stays conflict-free.
All fork customizations are applied in memory by the scripts, at generation
time, and exist only in the generated output.

Both scripts apply the same six customizations and print a confirmation line
for each:

1. **Default language set to English.** Patches upstream's Swedish fallback
   (`localStorage.getItem('ysfc-lang') || 'sv'` becomes `|| 'en'`). Only the
   first-visit default changes; the language toggle button and any saved
   visitor preference still work.

2. **Simple View default verified.** Not a patch - upstream already defaults to
   Simple View (`let initialAdvanced = false;`). The check exists to warn if
   upstream ever changes that default.

3. **Heading converted from `<h1>` to a linked `<h3>`.** Avoids competing with
   the host page's own `<h1>`, and links "YSFC Forge" to the upstream GitHub
   project. Everything after "Library Builder" is preserved verbatim.

4. **`.seltable-wrap` height patched from 251px to 259px.** Site-specific
   layout adjustment so the selection table lines up with the surrounding page.
   The 8px is relative to upstream's 251px, not an absolute value - if upstream
   retunes this, re-derive the offset rather than reapplying 259px.

5. **`body` selector re-scoped to `.forge-app`.** See the host page requirement
   above. Purely stylistic; applied to the stylesheet only. The JavaScript is
   untouched, including the locals named `body` in the binary parser and the
   `document.body.appendChild` used to trigger file downloads.

6. **All `h1`-scoped CSS mirrored onto `h3`.** Required by customization 3:
   upstream styles the header through five `h1` rules (the flex container plus
   `.ver`, `.sep`, `.spacer` and `.btn-group`). Without this the header buttons
   lose their right alignment and the heading loses its monospace font. The
   scripts find every `h1` rule and re-emit it for `h3`, so rules upstream adds
   later are carried over automatically.

The generated licence header carries a dual copyright notice: the original
work by Johan Adolfsson plus a line for the fork's modifications. MIT requires
the original notice to survive in distributed copies - it is added to, never
replaced.

## Warnings

Every customization reports either a success line or a `WARNING`. A warning
means the expected upstream text or markup was not found, so that customization
was skipped - the build still completes, but the output is missing that change.

**Treat any warning as upstream having changed its markup.** Locate the pattern
in the script, compare it against the new upstream source, and update it.
Customization 6 also reports a count (`mirrored 5 h1 CSS rule(s) onto h3`); if
that number changes, upstream's header CSS changed.

## Why the CSS stays inline

All three scripts keep the CSS inside the widget, stored in a
`<script type="text/plain">` block and injected into `document.head` by a
small script placed **before** the markup. Styles are therefore applied
before the content renders - there is no unstyled flash.

Do not move the CSS to a separate file loaded later in the page. That is
exactly what the retired `build-embedded.ps1` did, and the result rendered as
unstyled plain text.

## The external JavaScript

`build-library-embedded.ps1` and `build-sysex-embedded.ps1` both externalise
the application code. See "SysEx Converter: external JavaScript" below - the
same rules apply to both, including the deferral warning, and both read their
target path from `$JsBaseUrl` at the top of the script.

`$JsBaseUrl` is a **root-relative** path: the leading `/` makes the browser
resolve it from the site root, not from the page the widget sits on, so the
widget works at any page depth. Verified with the widget served from
`/tools/library-builder/` - the script still resolved to
`/wp-content/uploads/...`. If WordPress is installed in a subdirectory,
include that prefix in `$JsBaseUrl`. A full absolute URL would also work but
hard-codes the domain and breaks on staging copies.

## Backups

Before generating new files, existing ones are renamed using:
ysfc-library-builder-embed.YYYYMMDD.HHMMSS.html
ysfc-library-builder.YYYYMMDD.HHMMSS.js
ysfc-sysex-converter.YYYYMMDD.HHMMSS.html
ysfc-sysex-converter.YYYYMMDD.HHMMSS.js
ysfc-library-builder.YYYYMMDD.HHMMSS.html

Each script keeps the newest `$BackupsToKeep` backups (default 5) of each of
its own outputs and deletes the rest at the end of every run. Change the value
at the top of the script; 0 keeps none.

The cleanup regex matches only the exact `name.YYYYMMDD.HHMMSS.ext` form, so a
current output file can never be deleted by it. Each script only ever prunes
its own outputs.

The split builds also back up **only the file that actually changed**, so an
unchanged .js does not accumulate identical copies.

## Source File
Both scripts automatically detect the latest upstream file matching:
ysfc_forge_library_builder_v*.html
This avoids manual updates when upstream changes the version number.

## Workflow
1. Update main from upstream  
2. Rebase itb-custom  
3. Run the scripts in this folder  
4. Check that all six `itb-custom:` lines appear with no warnings  
5. Use the generated files in your HTML/JS container

After an upstream sync, confirm the source file still matches upstream exactly:

    git rev-parse upstream/main:tools/ysfc_forge_library_builder_v15_46.html
    git rev-parse itb-custom:tools/ysfc_forge_library_builder_v15_46.html

The two hashes must be identical. If they are not, the source file has been
modified and should be restored from `upstream/main`.

## Testing the output

The Elementor editor does **not** execute scripts inside HTML widgets. In the
editor the embed shows upstream's inline Swedish text and the buttons do
nothing - this is expected and not a fault in the build. Test using Preview or
the live page.

For a true first-visit test use a private/incognito window: a saved language or
theme preference in `localStorage` will otherwise override the defaults.

## Notes
- Do not edit generated files manually.
- Do not edit the tracked source HTML - add a build-time patch instead.
- All read/write operations use UTF-8.
- The .ps1 scripts are saved with a UTF-8 BOM, which Windows PowerShell 5.1
  needs in order to parse them correctly.
- Generated files are ignored via .gitignore.
