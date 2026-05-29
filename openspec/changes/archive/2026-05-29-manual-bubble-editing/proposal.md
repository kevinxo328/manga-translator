## Why

The automatic bubble detector (`ComicTextDetectorService`) misses bubbles (small SFX, hand-drawn balloons, non-standard shapes) and sometimes mis-frames them, but users currently have no way to fix either problem. The only recovery path is re-running detection with different settings, which discards everything and rarely improves the specific failure. Users need a per-page editing mode where they can add missing bubbles, move/resize miss-framed ones, delete false positives, and reorder reading sequence — then re-OCR and re-translate only what changed.

## What Changes

- Add a **per-page edit mode** entered from a button in `TranslationSidebar` (not the global toolbar). Only enabled when the page is in `PageState.translated`.
- Inside edit mode, allow users to:
  - **Draw** new bubble boxes by drag on empty canvas (min 20×20 image pixels).
  - **Move** existing boxes by drag.
  - **Resize** existing boxes via 8 handles (4 corners + 4 edges).
  - **Delete** selected boxes via `Delete`/`Backspace`.
  - **Multi-select** with `Shift+click` (add) and `Cmd+click` (toggle); `Cmd+A` selects all.
  - **Nudge** selected boxes with arrow keys (1 px) or `Shift`+arrow (10 px) in image coordinates.
  - **Reorder** the reading sequence by drag-to-reorder in `TranslationSidebar`.
  - **Undo / Redo** every edit action with `Cmd+Z` / `Cmd+Shift+Z`; stack cleared on commit.
- Track each `BubbleCluster` as **manual or not** via a new `isManual: Bool` field; flag becomes `true` for newly drawn boxes and for auto boxes whose geometry was edited.
- On **commit (Done / `Cmd+Return`)**: re-OCR only dirty boxes (new + geometry-changed), then re-translate the whole page once (single-page path); for LLM engines, feed in the **immediately preceding ≤3 translated pages** as `recentPageSummaries`, looked up by page index rather than from the rolling buffer.
- On **cancel (Cancel / `Cmd+.`)**: discard the entire edit session and restore the pre-edit state byte-for-byte.
- Disable page-switching UI (next/prev buttons, sidebar thumbnail clicks, ←/→ arrow keys) while edit mode is active — no modal alert; the controls are simply inert until commit or cancel.
- **Reading order for new boxes**: insert each newly drawn box into the existing order using **nearest-neighbour insertion** (Euclidean distance between box centres, in image pixel coordinates), placed immediately *after* its nearest neighbour in the current sequence. This is explicitly a best-effort heuristic, not a geometric re-sort; users refine via sidebar drag.
- **Box constraints**: clamp every box to image bounds during drag (no overflow); overlap between boxes is fully allowed (OCR runs per-box independently).
- **Cache round-trip**: persist `isManual` in the SQLite `translation_cache` JSON so editing decisions survive across sessions.

## Capabilities

### New Capabilities
- `manual-bubble-editing`: the per-page edit-mode capability covering entry/exit lifecycle, draw/move/resize/delete/multi-select operations, undo stack, dirty tracking, commit/cancel semantics, page-switch lock, and keyboard shortcut surface.

### Modified Capabilities
- `image-viewer`: gains an `editing` overlay layer (selection handles, drag-to-draw gesture, marquee) on top of today's static `BubbleOverlay`; viewing behaviour outside edit mode is unchanged.
- `reading-order`: adds the nearest-neighbour insertion rule for newly added boxes, and supports an externally supplied manual order (from sidebar drag) that is preserved across edits — `ReadingOrderSorter` is no longer the sole source of `index`.
- `translation-cache`: bubble JSON gains an `isManual` field (default `false` on decode for backward compatibility).
- `contextual-translation`: adds a `summariesPreceding(pageIndex:)` helper so single-page re-translation triggered by an edit commit pulls context from pages `[N-3..<N]` instead of the rolling "most recently translated" buffer.
- `retranslate`: edit-commit re-translation reuses the per-page retranslate code path; the trigger surface expands from "user pressed Re-translate" to "user committed an edit".

## Impact

- **Code**:
  - `MangaTranslator/Models/Models.swift`: add `BubbleCluster.isManual: Bool`; add edit-session types (`EditAction`, `EditSessionState`).
  - `MangaTranslator/Views/ImageViewer.swift`: add edit-mode rendering and gesture handling.
  - `MangaTranslator/Views/TranslationSidebar.swift`: add Edit / Done / Cancel buttons, dirty visual states on `TranslationCard`, drag-to-reorder.
  - `MangaTranslator/Views/ContentView.swift`: wire page-switch lock to edit state.
  - `MangaTranslator/ViewModels/TranslationViewModel.swift`: add edit session state, dirty tracking, commit pipeline, `summariesPreceding(pageIndex:)` helper.
  - `MangaTranslator/Services/ReadingOrderSorter.swift`: add `insertNearestNeighbour(_:into:)`.
  - `MangaTranslator/Services/CacheService.swift`: extend bubble JSON encode/decode with `isManual` (default `false`).
- **No new entitlements, no new dependencies, no new ML models.**
- **Test surface**: pure-logic units (sorter insertion, undo stack, dirty tracking, summariesPreceding) covered by `MangaTranslatorTests`; SwiftUI gesture surface verified manually via the running app.
- **Performance**: edit operations are local; commit re-runs OCR for ≤ all-on-page bubbles in the worst case (no worse than first-time processing).
- **Risk**: SwiftUI gesture composition (drag-to-draw vs. drag-existing-box vs. click-to-select) needs careful first-event hit-testing and cancellation handling; covered in `design.md`.
