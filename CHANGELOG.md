# Changelog

## v1.0.1 (2026-02-12)

### Bug Fixes

- Reset translation sidebar scroll position when switching between images

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
