# Changelog

## v1.3.0 (2026-04-22)

### New Features

- **Improved Text Recognition** — Upgraded the built-in Japanese text recognition engine to the latest 2025 version for better accuracy.

## v1.2.5 (2026-04-22)

### Bug Fixes

- Fixed high-resolution manga scans (e.g. 600 DPI) appearing tiny in the viewer and showing bubble indicators in the wrong positions.

## v1.2.4 (2026-04-08)

### New Features

- **Cache Size Display** — You can now see how much disk space the translation cache is using, right in Settings.

### Bug Fixes

- Fixed the path bar showing a temporary folder path instead of your file's actual location while a translation was in progress.

### Improvements

- Languages are now shown with their flag and full name instead of short language codes, making it easier to pick the right language.

## v1.2.3 (2026-04-07)

### Bug Fixes

- Fixed GitHub Copilot showing "no models available" after upgrading to v1.2.1 or v1.2.2.

## v1.2.2 (2026-04-07)

### New Features

- **System Menu Support** — Open images directly from the macOS menu bar for a more seamless workflow.
- **Path Bar Footer** — Toggle a new footer bar at the bottom of the window to see exactly where your current image is stored.

## v1.2.1 (2026-04-07)

### Improvements

- GitHub Copilot models are now grouped by tier (Premium, Lite, Standard) so you can easily pick the right one for your needs. The app also falls back to your organization's Copilot endpoint automatically if the personal one isn't available.

## v1.2.0 (2026-04-07)

### New Features

- **GitHub Copilot Support** — You can now use GitHub Copilot as a translation engine. Select it in Settings to translate manga pages using your existing Copilot subscription — no separate API key needed. Choose from available Copilot models to suit your needs.

## v1.1.9 (2026-04-04)

### Improvements

- You can now dismiss the error message that appears when a page fails to translate, instead of having it stay on screen.

## v1.1.8 (2026-03-23)

### Bug Fixes

- Fixed the page indicator pill showing an unexpected background.

## v1.1.7 (2026-03-12)

### Improvements

- Toolbar buttons (Glossary, language picker, translation engine) now match the native macOS style — no more mismatched borders or backgrounds.
- The divider between the image and the translation panel is now a clean, subtle line instead of a heavy split-view handle.
- The translation panel background now blends seamlessly with the rest of the window.

## v1.1.6 (2026-03-12)

### Bug Fixes

- Fixed visual layout and spacing issues across the app.

## v1.1.5 (2026-03-10)

### Bug Fixes

- Fixed language labels (like "ZH-TW") being cut off in the toolbar when the window is small.
- Fixed the "Clear Cache" explanation text in Settings not aligning correctly.

## v1.1.4 (2026-03-10)

### Improvements

- Refactored language selection pickers to use international standard short codes (JA, EN, ZH-TW) for better consistency and space efficiency.

## v1.1.3 (2026-03-10)

### Bug Fixes

- Fixed automatic update checks not running even when "Automatically check for updates" was enabled.

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
