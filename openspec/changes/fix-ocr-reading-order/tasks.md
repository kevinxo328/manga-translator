## 1. Tests — BubbleReorder pure function (Red)

- [ ] 1.1 Create `MangaTranslatorTests/BubbleReorderTests.swift` with `@Suite("BubbleReorder")`
- [ ] 1.2 Write test: `move` swaps two adjacent items and produces sequential indices [0, 1, 2]
- [ ] 1.3 Write test: `move` from position 0 upward (to: -1) returns list unchanged
- [ ] 1.4 Write test: `move` from last position downward (to: count) returns list unchanged
- [ ] 1.5 Write test: `move` from same position to same position returns list unchanged
- [ ] 1.6 Write test: `move` single-element list returns list unchanged
- [ ] 1.7 Write test: after `move`, all indices are sequential starting from 0
- [ ] 1.8 Write test: `move` from position 2 to position 0 produces correct order [C, A, B]

## 2. Implement BubbleReorder (Green)

- [ ] 2.1 Add `enum BubbleReorder` with `static func move(bubbles:from:to:) -> [TranslatedBubble]` to `MangaTranslator/Models/Models.swift`
- [ ] 2.2 Run tests — all BubbleReorder tests pass

## 3. Tests — retranslatePage (Red)

- [ ] 3.1 Write test: verify that `retranslatePage` extracts existing `BubbleCluster` from `.translated` state (test the bubble extraction logic as a pure function if possible)

## 4. Implement ViewModel changes (Green)

- [ ] 4.1 Add `moveBubble(from:to:)` to `TranslationViewModel` — calls `BubbleReorder.move`, updates page state and cache
- [ ] 4.2 Add private `retranslatePage(at:)` — reuses existing bubbles, only re-translates
- [ ] 4.3 Modify `retranslateCurrentPage()` to call `retranslatePage(at:)`
- [ ] 4.4 Modify `retranslateAllPages()` to call `retranslatePage(at:)` for each page

## 5. Implement Sidebar drag-to-reorder UI

- [ ] 5.1 Add `onMove: ((Int, Int) -> Void)?` parameter to `TranslationSidebar`
- [ ] 5.2 Add `.draggable(bubble.id.uuidString)` to each card
- [ ] 5.3 Add `.dropDestination(for: String.self)` to handle drops and call `onMove`
- [ ] 5.4 Add `@State` for drag-over visual feedback (highlight drop target position)

## 6. Wire up ContentView

- [ ] 6.1 Pass `onMove` callback from `ContentView` to `TranslationSidebar`, calling `viewModel.moveBubble(from:to:)`

## 7. Xcode project

- [ ] 7.1 Add `BubbleReorderTests.swift` to test target in `project.pbxproj`

## 8. Verify

- [ ] 8.1 Run all tests — no regressions
- [ ] 8.2 Manual test: drag reorder in sidebar → badges update in ImageViewer
- [ ] 8.3 Manual test: reorder → re-translate → order preserved
- [ ] 8.4 Manual test: re-translate all pages → order preserved on each page
- [ ] 8.5 Manual test: switch pages and back → reordered state cached
