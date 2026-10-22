# 05: Establish SwiftUI behaviour and UI-test seams

**What to build:** Critical SwiftUI interactions can be verified through stable state/action seams and a focused macOS UI-test target instead of source-text inspection.

**Blocked by:** None (can start immediately).

**Status:** claimed

- [ ] A focused macOS UI-test target can launch the app deterministically.
- [ ] Critical controls expose stable accessibility identifiers without changing user-facing copy.
- [ ] State-to-action decisions have a narrow fast-test seam.
- [ ] Removing a test-only critical control/action mapping demonstrably makes the focused test red and restoration green.

