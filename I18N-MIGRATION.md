# i18n Migration Manifest

This repository keeps English as the canonical language. Brazilian Portuguese
is a parallel locale under `i18n/pt-BR/`; it never replaces canonical files.

## Canonical mapping

| Canonical English | Brazilian Portuguese mirror |
| --- | --- |
| `certification/<path>.md` | `i18n/pt-BR/certification/<path>.md` |
| `practice/labs/<path>.sql` | `i18n/pt-BR/practice/labs/<path>.sql` |

For SQL labs, executable SQL, identifiers, product names, and documented error
messages remain unchanged. Comments, section banners, instructions, and
expected-result notes are localized.

## Migration rules

1. Copy the Portuguese source into its mirror before changing the canonical
   file to English.
2. Preserve relative paths and headings so that drift can be compared by path.
3. Do not publish personal prompts, audit reports, generated DOCX files, or
   temporary plans as translated study content.
4. Use a locale-aware tool invocation for generated artifacts, for example
   `python scripts/build_docx.py --locale en` or `--locale pt-BR`.
5. Validate Markdown links and SQL structure after every domain batch.

## Current migration batches

- **Tooling:** `scripts/build_docx.py`, `build-docx.bat`, and
  `convert-drag-drop.bat` expose English interfaces and accept a locale.
- **Labs:** 42 SQL labs are mirrored under `i18n/pt-BR/practice/labs/` before
  their canonical counterparts are converted to English.
- **Theory:** the pt-BR tree currently has path counterparts for 56 of the 98
  canonical Markdown files. The remaining 42 files are translated in domain
  batches, beginning with resources, practice material, and cheat sheets.

## Release checklist

- [ ] Every published pt-BR file has a canonical English counterpart.
- [ ] No Portuguese prose or SQL comments remain outside `i18n/pt-BR/`.
- [ ] Locale-relative links resolve.
- [ ] `build_docx.py --locale en` and `--locale pt-BR` complete successfully.
- [ ] Generated outputs and private audit material are excluded from Git.
