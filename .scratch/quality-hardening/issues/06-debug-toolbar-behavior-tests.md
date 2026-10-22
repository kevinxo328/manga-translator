# 06: Replace debug-log and toolbar implementation-text tests

**What to build:** Users are protected by tests that exercise debug actions and batch cancellation, not tests that inspect SwiftUI layout or source spelling.

**Blocked by:** 05: Establish SwiftUI behaviour and UI-test seams.

**Status:** ready-for-agent

- [ ] Clear and export actions are covered through observable state or UI interaction.
- [ ] A processing batch exposes cancellation and invokes cancellation when selected.
- [ ] Sorting expectations call a product seam rather than reimplement sorting in the test.
- [ ] Removing the relevant product action makes a replacement test red and restoration green.
- [ ] Corresponding DebugLogView and ContentView source-text tests are retired.

