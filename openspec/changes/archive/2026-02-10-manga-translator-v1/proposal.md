## Why

macOS lacks a lightweight, native manga translation tool. Existing solutions are either web-based (slow, privacy concerns), require large ML model downloads (500MB+), or produce poor translations by handling text line-by-line without context. Manga readers who want to read untranslated works need a fast, small-footprint app that understands speech bubbles as semantic units and leverages LLMs for context-aware translation.

## What Changes

- New macOS SwiftUI application (sandboxed) targeting macOS 13+
- OCR via macOS Vision framework (zero additional dependencies)
- Speech bubble detection via spatial clustering of text regions
- Reading order detection via spatial heuristics + LLM correction
- Switchable translation backends: DeepL, Google Translate, OpenAI, Claude
- LLM backends receive full-page bubble context for superior translation quality
- Batch processing: open folders or compressed archives (.zip/.cbz)
- Progressive UX: pages translate in background, viewable as they complete
- Translation cache in SQLite for instant re-display of previously translated pages
- API keys stored in macOS Keychain
- Six translation directions across Japanese, English, and Traditional Chinese
- UI: image viewer with bubble overlays (hover) + sidebar translation list

## Capabilities

### New Capabilities
- `ocr-pipeline`: Vision framework OCR integration, text region detection, and coordinate normalization
- `bubble-detection`: Spatial clustering of text observations into speech bubble groups
- `reading-order`: Bubble ordering via spatial heuristics with LLM-assisted correction
- `translation-service`: Switchable translation backends (DeepL, Google, OpenAI, Claude) with unified protocol
- `translation-cache`: SQLite-based caching keyed by image hash + language pair + engine
- `image-viewer`: Main UI with image display, bubble overlay, hover popover, and sidebar translation list
- `batch-processing`: Folder and archive (.zip/.cbz) input with progressive background translation
- `settings-management`: User preferences (UserDefaults) and API key storage (Keychain)

### Modified Capabilities

(none - greenfield project)

## Impact

- **New Xcode project**: Replaces current Python project structure entirely
- **Dependencies**: No external Swift packages required for core functionality (Vision, SQLite3, Keychain are all system frameworks). HTTP networking via URLSession.
- **APIs**: Requires user-provided API keys for translation services (DeepL, Google Cloud Translation, OpenAI, Anthropic)
- **System frameworks**: Vision, NaturalLanguage, UniformTypeIdentifiers, Security (Keychain), SQLite3
