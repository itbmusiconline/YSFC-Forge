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

### build-embedded.ps1
Generates:
- ysfc-library-builder-style.css  
- ysfc-library-builder-body.html  
(Splits the content of the <style> and <body> into separate files)

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

## Backups
Before generating new files, existing ones are renamed using:
ysfc-library-builder.YYYYMMDD.HHMMSS.html
ysfc-library-builder-style.YYYYMMDD.HHMMSS.css
ysfc-library-builder-body.YYYYMMDD.HHMMSS.html

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
