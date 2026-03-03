# Changelog

## v1.1.0 (2026-03-03)

### New Features

- **Glossary System** — Create named glossaries and define your own source → target term mappings. Active glossary terms are automatically injected into every translation request, so character names, technique names, and place names stay consistent across pages. The glossary picker lives in the main toolbar for quick access.
- **Auto-detection of Proper Nouns** — When using Claude or OpenAI, the translator automatically detects new proper nouns during translation and saves them to your active glossary. Auto-detected terms are visually marked so you can review and edit them at any time.
- **Glossary for DeepL and Google Translate** — Glossary terms now also apply when using DeepL or Google Translate. Source terms are wrapped using each API's native preservation mechanism before translation, so they survive the translation process reliably.
- **Cross-page Context** — When using Claude or OpenAI, the translated content of the last 3 pages is included in each new translation request. This helps the model maintain narrative continuity — characters introduced on earlier pages are referenced consistently in later dialogue.

## v1.0.5 (2026-02-23)

### Bug Fixes

- Fixed ⌘O not working when an image is already open

## v1.0.4 (2026-02-14)

### Improvements

- App now checks for updates when you switch back to it, so you'll discover new versions faster even if you leave the app open for a long time

## v1.0.3 (2026-02-13)

### Bug Fixes

- Fixed arrow key navigation between bubbles sometimes not working correctly
- Fixed bubble numbering showing duplicate numbers in some cases

## v1.0.2 (2026-02-13)

### Bug Fixes

- Fixed version number showing 1.0.0 instead of actual version after update
- Fixed "You're up to date" showing incorrectly when a new version is available

### Improvements

- App now automatically checks for updates on launch
- Smaller "Check for Updates" button in Settings for a cleaner look

## v1.0.1 (2026-02-12)

### New Features

- **OpenAI Compatible**: Now supports any OpenAI-compatible API provider (local LLMs, Azure OpenAI, etc.) with configurable base URL and model
- Added reset buttons for base URL and model fields in OpenAI Compatible settings
- Auto-corrects common URL and model name formatting mistakes in settings

### Improvements

- Default OpenAI model updated to `gpt-5`
- Sidebar now scrolls back to top when switching between images

## v1.0.0 (2026-02-11)

Initial release of Manga Translator — a macOS app for translating manga with OCR and AI-powered translation.

### Features

- Automatic Japanese text recognition (Manga OCR)
- Automatic speech bubble detection and highlighting
- Translation powered by DeepL, Claude, or OpenAI
- Choose specific models for Claude and OpenAI in settings
- Re-translate individual bubbles on demand
- Navigate between bubbles with keyboard shortcuts and auto-scroll
- Import images via drag-and-drop or file picker
- Clear translation cache from settings
- Auto-update support
- DeepL Pro plan auto-detection
