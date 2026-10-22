# 07: Replace Copilot Settings implementation-text tests

**What to build:** Copilot model loading states present the correct selectable, auto-only, loading, unavailable, and retry behaviour through tested UI and state contracts.

**Blocked by:** 05: Establish SwiftUI behaviour and UI-test seams.

**Status:** completed

- [x] Auto-only and selectable catalogs expose only valid model choices.
- [x] Loading, unavailable, and failed states expose distinct observable user outcomes, including retry where applicable.
- [x] A deliberately broken state/action mapping makes the successor test red and restoration green.
- [x] SettingsView source-text scans and obsolete old-copy absence assertions are retired.

## Verification

- `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' -only-testing:MangaTranslatorTests/SettingsViewCopilotTests` passes with the restored mapping.
- `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' -only-testing:MangaTranslatorUITests/MangaTranslatorUITests/testCopilotRetryTransitionsToLoading` observes the Retry control and its loading transition.
- Temporarily mapping `.failed` to `.none` makes `loadingNoCompatibleAndFailedStatesExposeDistinctControls()` fail; restoring `.retry` makes the focused suite pass.

