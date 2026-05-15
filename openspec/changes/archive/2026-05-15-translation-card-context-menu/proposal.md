## Why

Users need a quick way to copy translation or OCR text from the sidebar without selecting text manually. A right-click context menu on each translation card provides standard macOS UX for clipboard operations.

## What Changes

- `TranslationCard` gains a `.contextMenu` modifier with three copy actions:
  - **Copy Translation** — copies `bubble.translatedText` to clipboard
  - **Copy Original Text** — copies `bubble.bubble.text` (full, not limited by `lineLimit`) to clipboard
  - **Copy Both** — copies both fields combined as a single formatted string

## Capabilities

### New Capabilities

- `translation-card-context-menu`: Right-click context menu on translation sidebar cards for clipboard copy operations

### Modified Capabilities

(none)

## Impact

- `MangaTranslator/Views/TranslationSidebar.swift` — only file changed
- No ViewModel, Model, or Service changes required
- No new dependencies
