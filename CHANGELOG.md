# Changelog

## v1.1.2 (2026-03-10)

### Improvements

- The app no longer prompts macOS for Keychain access repeatedly during a session, reducing interruptions.
- Settings panel is now taller, making it easier to browse all options without scrolling.

### Changes

- Removed Claude (Anthropic) as a translation engine option. Gemini, DeepL, and OpenAI remain available.

## v1.1.1 (2026-03-09)

### Bug Fixes

- Fixed translations occasionally appearing in the wrong speech bubble when using Claude or OpenAI.
- Fixed a loading indicator that sometimes stayed visible after batch translation finished.
- Fixed settings changes (language, engine, model) not taking effect until the app was restarted.

## v1.1.0 (2026-03-03)

### New Features

- **Glossary** — Tired of character names being translated differently every few pages? Now you can create a glossary and pin your preferred translations for names, places, and special terms. The translator will follow your glossary on every page, across all four translation engines.
- **Auto-detected terms** — When using Claude or OpenAI, the translator picks up new names and terms on its own and adds them to your glossary automatically. You can review, edit, or remove them anytime.
- **Better dialogue continuity** — When using Claude or OpenAI, the translator now remembers what happened in the last few pages. This means follow-up lines, callbacks, and mid-conversation pages read much more naturally.

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
