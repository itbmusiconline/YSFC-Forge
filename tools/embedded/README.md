# Embedded Tools for YSFC Forge Library Builder

## Purpose
This folder contains local PowerShell scripts used to generate embedded 
versions of the YSFC Forge Library Builder for use when the tool is not 
hosted directly, but in third party web builders, for example WordPress. 
These scripts are part of the `itb-custom` branch and are not included 
in the upstream project.

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
4. Use the generated files in your HTML/JS container

## Notes
- Do not edit generated files manually.
- All read/write operations use UTF-8.
- Generated files are ignored via .gitignore.
