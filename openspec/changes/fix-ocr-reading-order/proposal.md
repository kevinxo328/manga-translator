## Why

`ReadingOrderSorter` uses purely geometric heuristics (partition into rows by vertical overlap, sort right-to-left within rows). This frequently produces incorrect reading order for complex manga layouts — multi-panel pages where bubbles from different panels share similar Y positions, diagonal panel arrangements, and non-standard layouts. Users have no way to correct the order after OCR.

Additionally, the "re-translate" function always re-runs OCR, so even if a future correction mechanism existed, it would be overwritten on retranslation.

## What Changes

- Add manual drag-to-reorder capability in the translation sidebar so users can fix bubble reading order
- Extract a pure `BubbleReorder.move` function for testability
- Separate re-translation from re-OCR: "re-translate" now keeps existing bubbles and their order, only re-sends to the translation API
- Both single-page and all-pages re-translation follow this new behaviour

## Capabilities

### New Capabilities
- `reading-order`: Manual drag-to-reorder bubbles in the sidebar UI
- `reading-order`: `BubbleReorder.move` pure function for reindexing bubbles

### Modified Capabilities
- `reading-order`: Re-translate preserves existing bubble order (no re-OCR)

## Impact

- `MangaTranslator/Models/Models.swift` — new `BubbleReorder` enum
- `MangaTranslator/ViewModels/TranslationViewModel.swift` — `moveBubble`, `retranslatePage`
- `MangaTranslator/Views/TranslationSidebar.swift` — drag-to-reorder UI
- `MangaTranslator/Views/ContentView.swift` — wire up `onMove` callback
- `MangaTranslatorTests/BubbleReorderTests.swift` — new test suite
