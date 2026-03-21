## Context

`ReadingOrderSorter` sorts bubbles geometrically (row-based, right-to-left). Complex manga layouts produce wrong order. Users need a way to manually correct the reading order. Additionally, "re-translate" currently re-runs OCR, which would overwrite any manual corrections.

## Goals / Non-Goals

**Goals:**
- Allow users to drag-reorder bubbles in the sidebar
- Extract `BubbleReorder.move` as a testable pure function
- Make re-translate (current page + all pages) only re-translate, not re-OCR
- Preserve manual reorder through cache

**Non-Goals:**
- Changing the geometric sorting algorithm in `ReadingOrderSorter`
- Adding LLM-based automatic reordering (future work)
- Adding panel detection
- Changing the ImageViewer overlay rendering logic (it already reads from `index`)

## Decisions

### Extract `BubbleReorder.move` as a pure function
The `TranslationViewModel` is `@MainActor` and depends on services (OCR, Cache, Keychain), making it hard to unit test. By extracting the reorder logic into a pure static function `BubbleReorder.move(bubbles:from:to:) -> [TranslatedBubble]`, we can TDD the core logic independently.

**Location:** Bottom of `Models.swift` — co-located with `TranslatedBubble` which it operates on.

### Drag-to-reorder via `.draggable` / `.dropDestination`
Preserve the existing `ScrollView` + `VStack` sidebar structure. Use SwiftUI's `.draggable` and `.dropDestination` modifiers on each card for native drag-and-drop. This avoids switching to `List` which would change the sidebar's visual style.

**Alternative considered:** `List` with `.onMove` — simpler code but changes sidebar appearance (row separators, background).

**Alternative considered:** Up/down arrow buttons — simpler implementation but less intuitive UX than drag.

### Separate re-translate from re-OCR
New private method `retranslatePage(at:)`:
- If the page is in `.translated` state: extract `BubbleCluster` from existing `TranslatedBubble`, keep their indices, send only to translation API
- If the page is not yet translated: fall back to full `translatePage(at:, bypassCache: true)`
- On failure: restore previous translation (not show error state)

`retranslateCurrentPage()` and `retranslateAllPages()` both switch to calling `retranslatePage(at:)`.

### Cache update on reorder
When user reorders bubbles, immediately update the cache so the order persists across page switches. Use existing `cacheService.store()`.

## Risks / Trade-offs

- [Drag-and-drop with `ScrollView` is more complex than `List.onMove`] → Acceptable trade-off to preserve existing sidebar visual style
- [Re-translate without re-OCR means OCR errors won't be corrected on retranslate] → This is the intended behaviour per user request; users can reload the image to trigger fresh OCR if needed
- [`.draggable`/`.dropDestination` requires macOS 13+] → The app already targets macOS 13+ (uses other macOS 13 APIs)
