# Changelog

## v1.5.3 (2026-06-12)

### Bug Fixes

- Fixed translation failures by adding automatic retries for single-page translations.
- Fixed custom reading order of speech bubbles being lost when re-translating a page.

### Improvements

- Reuses cached translations when switching translation engines so that you don't have to wait or spend credits to re-translate the same page.
- Batched translation requests for DeepL and Google Translate so that translating multiple pages is significantly faster.
- Improved glossary processing to only load relevant terms for the current page, making translations faster and reducing translation costs.

## v1.5.2 (2026-06-11)

### Bug Fixes

- Fixed pages from different chapters or volumes getting mixed up when importing a manga folder that contains subdirectories.
- Fixed translated text occasionally appearing in the wrong speech bubbles when using DeepL or Google Translate.
- Fixed translation formatting bugs (like broken tags or garbled text) when glossary terms contained overlapping names (such as "Tokyo" and "Tokyo Tower").
- Fixed translation quality degrading after encountering blank pages, covers, or action-only pages, by ensuring they do not push previous story context out of the translator's memory.
- Fixed the app freezing or becoming unresponsive while verifying newly downloaded translation files.

### Improvements

- Added safety limits to translation requests to prevent the translator from getting stuck in repetitive loops and wasting API usage.
- Optimized the translation cache to use significantly less disk space, while automatically cleaning up old data to reclaim storage.
- Sped up glossary term lookups and made adding auto-detected names much faster.

## v1.5.1 (2026-06-05)

### Improvements

- Expanded target language support to include French, German, Indonesian, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, and Vietnamese, so that you can translate manga into more of your preferred languages.
- Added a quick-create glossary option in the main toolbar with real-time name validation, so that you can quickly set up error-free glossaries without leaving your main view.

## v1.5.0 (2026-05-29)

### New Features

- **Manual Speech Bubble Editing** — You can now manually edit the detected text inside speech bubbles and trigger a retranslation on the spot, making it easy to fix any text recognition mistakes.

## v1.4.8 (2026-05-24)

### Improvements

- Improved the settings interface with a dedicated glossary management tab and support for active renaming, so you can easily review and update your custom term translations.

## v1.4.7 (2026-05-23)

### New Features

- **Multi-Page Translation** — Translate consecutive pages together in batches. This makes translation dramatically faster and allows the translator to maintain context between pages for much more cohesive and accurate storytelling.

### Bug Fixes

- Fixed an issue where the available GitHub Copilot models would fail to load or be missing from the model selection dropdown.
- Fixed an issue where a network disruption or unexpected quit during model downloading could result in a corrupted model installation; downloads are now handled transactionally with automatic recovery.
- Fixed silent translation or saving failures by adding structured error feedback in the interface, while keeping your privacy safe by automatically filtering sensitive API keys and tokens from error messages and logs.

### Improvements

- Added support for recognizing text in inverted speech bubbles (white text on a dark background), improving accuracy during action-heavy or highly-styled scenes.

## v1.4.6 (2026-05-15)

### New Features

- **Settings Redesign** — A modern, sidebar-based layout for settings, making it easier to navigate and adjust your preferences.
- **Copy to Clipboard** — You can now right-click on any translation to quickly copy the text to your clipboard.

## v1.4.5 (2026-05-15)

### Bug Fixes

- Fixed a build issue where a required internal bundle was missing from the distributed DMG, preventing the high-accuracy OCR from working correctly.

### Improvements

- **Reduced Memory Usage** — Improved memory management for high-accuracy text recognition, ensuring the app remains responsive even when processing many pages in a row.

## v1.4.4 (2026-05-14)

### Improvements

- **Optimized Translation** — Pages already in the source language are now skipped automatically, and empty or meaningless speech bubbles are ignored, making translation noticeably faster.
- Source language options are now limited to Japanese and English, keeping the picker simple and accurate.
- Improved text recognition quality with better image processing before OCR runs.

### Bug Fixes

- Fixed an issue where an unsupported source language saved from a previous version could cause incorrect behavior on startup.

## v1.4.3 (2026-05-13)

### New Features

- **Debug Logs** — The app now keeps a persistent log file so you can easily share diagnostic information when something isn't working as expected.

### Bug Fixes

- Fixed a security issue where a maliciously crafted API server address could potentially expose your API credentials.

## v1.4.2 (2026-05-13)

### Bug Fixes

- Fixed an issue where text recognition might skip or misread small text in complex layouts.

### Improvements

- Improved processing speed so that pages load and translate faster.

## v1.4.1 (2026-05-09)

### Improvements

- **Improved Recognition Accuracy** — Refined the high-accuracy OCR engine's spatial awareness to provide more precise text recognition, especially in complex manga layouts.

## v1.4.0 (2026-05-07)

### New Features

- **High-Accuracy PaddleOCR** — Added support for the high-accuracy PaddleOCR engine, optimized specifically for Apple Silicon (M-series) chips to provide superior text recognition.

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
