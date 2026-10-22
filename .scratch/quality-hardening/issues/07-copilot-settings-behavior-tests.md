# 07: Replace Copilot Settings implementation-text tests

**What to build:** Copilot model loading states present the correct selectable, auto-only, loading, unavailable, and retry behaviour through tested UI and state contracts.

**Blocked by:** 05: Establish SwiftUI behaviour and UI-test seams.

**Status:** ready-for-agent

- [ ] Auto-only and selectable catalogs expose only valid model choices.
- [ ] Loading, unavailable, and failed states expose distinct observable user outcomes, including retry where applicable.
- [ ] A deliberately broken state/action mapping makes the successor test red and restoration green.
- [ ] SettingsView source-text scans and obsolete old-copy absence assertions are retired.

