# Changelog

## v1.0.3 (2026-02-13)

### Bug Fixes

- **Bubble Navigation**: Fixed arrow key navigation breaking when OCR produces duplicate bubble indices by tracking selection with UUID instead of index
- **Bubble Numbering**: Display sequential numbers (1, 2, 3...) based on sorted position instead of raw index, preventing duplicate numbers

## v1.0.2 (2026-02-13)

### Bug Fixes

- **Version Display**: Fixed app showing incorrect version (1.0.0) after update by passing version from git tag to xcodebuild
- **Auto-Update Detection**: Fixed Sparkle version comparison failing due to "v" prefix in appcast version strings, causing "You're up to date" even when a newer version exists

### Improvements

- **Auto-Update Check**: Explicitly enabled automatic update checks on launch via `SUAutomaticallyChecksForUpdates` in Info.plist
- **Check for Updates Button**: Reduced button size in Settings for consistent UI

## v1.0.1 (2026-02-12)

### Bug Fixes

- Reset translation sidebar scroll position when switching between images

### Features

- **OpenAI Compatible**: Renamed "OpenAI" to "OpenAI Compatible" with configurable base URL and free-text model input, enabling support for any OpenAI-compatible API provider (local LLMs, Azure OpenAI, etc.)
- **Reset to Default**: Added reset buttons for base URL and model fields in OpenAI Compatible settings
- **Input Sanitization**: Automatically strips trailing slashes from base URLs and leading slashes from model names to prevent common configuration errors

### Changes

- Default OpenAI model updated from `gpt-4o-mini` to `gpt-5`

## v1.0.0 (2026-02-11)

Initial release of Manga Translator — a macOS app for translating manga with OCR and AI-powered translation.

### Features

- **Manga OCR**: Integrated Manga OCR pipeline with ONNX models for accurate Japanese text recognition
- **Speech Bubble Detection**: Automatic detection and highlighting of speech bubbles in manga images
- **Multi-backend Translation**: Support for DeepL, Claude, and OpenAI translation backends
- **LLM Model Selection**: Choose specific models for Claude and OpenAI in settings
- **Re-translate**: Re-translate individual bubbles with full OCR + translate pipeline and cache bypass
- **Smart Skip**: Skip translation when source and target languages match or text is punctuation-only
- **Bubble Navigation**: Keyboard shortcuts for navigating between speech bubbles with auto-scroll
- **Drag & Drop / Click-to-Open**: Import manga images via drag-and-drop or file picker
- **Cache Management**: Clear translation cache from settings
- **Auto-update**: Sparkle-based auto-update with EdDSA signing
- **About Tab**: Application details and contact links in settings

### Bug Fixes

- Auto-detect DeepL API plan based on key suffix to support Pro users
- Fix file upload error from keyboard
- Improve batch translation progress tracking
- Auto-scroll sidebar to highlighted bubble on keyboard navigation
