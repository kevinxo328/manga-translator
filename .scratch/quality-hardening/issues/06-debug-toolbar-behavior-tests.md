# 06: Replace debug-log and toolbar implementation-text tests

**What to build:** Users are protected by tests that exercise debug actions and batch cancellation, not tests that inspect SwiftUI layout or source spelling.

**Blocked by:** 05: Establish SwiftUI behaviour and UI-test seams.

**Status:** completed

- [x] Clear and export actions are covered through observable state or UI interaction.
- [x] A processing batch exposes cancellation and invokes cancellation when selected.
- [x] Sorting expectations call a product seam rather than reimplement sorting in the test.
- [x] Removing the relevant product action makes a replacement test red and restoration green.
- [x] Corresponding DebugLogView and ContentView source-text tests are retired.

## Verification

- Reversing `TranslatedBubble.sortedByIndex` made both reading-order tests fail;
  restoring the product seam returned them to green.
- Removing the filtered delete from `DebugLogViewModel.clearLogs()` made the clear
  action tests fail; restoring it returned them to green.
- The complete `MangaTranslator` test scheme passed after restoration.

