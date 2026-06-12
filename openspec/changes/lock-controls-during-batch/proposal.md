## Why

During batch translation only the toolbar "Re-translate All" button is disabled. Every other pipeline-affecting control stays interactive, which causes two real problems:

1. **Race conditions**: switching the engine mid-batch fires `switchEngineForCurrentPage()` via the toolbar `onChange`, mutating page state concurrently with the batch pipeline. Pressing the sidebar Re-translate button or opening an Edit Mode session on an already-translated page races the batch pipeline the same way (Re-translate All re-processes that page underneath the edit session).
2. **Inconsistent output**: `preparePage` reads `preferences.sourceLanguage` / `targetLanguage` and the active glossary live per page, so changing them mid-batch produces a book half-translated with the old settings and half with the new ones, with diverging cache keys.

The same hazards apply to single-page translation flows (initial single-image translation, sidebar Re-translate, engine switch, Edit Mode commit): they never set `isProcessing` — only the page's own `.processing` state — yet they read the same live preferences mid-flight, so the toolbar pickers must also lock while any single-page translation is running.

## What Changes

- Introduce a unified lock predicate on the view model: translation is in flight when `isProcessing` is true (batch) **or** any page's state is `.processing` (single-page flows, including Edit Mode commit).
- Disable the following main-window controls while translation is in flight:
  - Open button (loading a new file would replace `pages` under the running pipeline)
  - Glossary picker
  - Source / target language pickers
  - Engine picker
  - Sidebar Re-translate button (currently gated only on the current page's `.processing` state; gains the batch condition)
  - Sidebar Edit button (currently enabled whenever the current page is `.translated`, even mid-batch; gains the batch condition)
- Guard the engine-switch handler (`switchEngineForCurrentPage()`) to ignore engine changes while translation is in flight. This is defense-in-depth: the Settings window binds the same `PreferencesService` pickers, so disabling the toolbar alone does not close the race.
- Page navigation (previous/next, page indicator) stays enabled — browsing during batch is an existing supported behavior.
- Settings-window pickers remain enabled; mid-batch language changes from Settings remain possible and are documented as a deferred decision in design.md.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `batch-processing`: new requirement — pipeline-affecting controls are locked while translation is in flight (batch or single-page).
- `glossary-management`: "Glossary picker in main UI" currently allows switching "at any time"; carve out the translation-in-flight window.
- `retranslate`: sidebar Re-translate button gating gains a batch-running condition; "Engine switch reuses per-engine cache" gains the rule that engine switches are not processed while translation is in flight.
- `manual-bubble-editing`: Edit button gating rule changes from "enabled iff page state is `.translated`" to "enabled iff page state is `.translated` AND no batch translation is running".

## Impact

- `MangaTranslator/Views/ContentView.swift` — toolbar items (Open, glossary, language pair, engine, `onChange` guard), sidebar parameter wiring.
- `MangaTranslator/Views/TranslationSidebar.swift` — possibly none beyond the existing `isProcessing` parameter, depending on wiring choice in design.
- `MangaTranslator/ViewModels/TranslationViewModel.swift` — new computed lock predicate (derived from existing `isProcessing` and `pages`; no new published property) and a guard in `switchEngineForCurrentPage()`.
- `MangaTranslatorTests/` — view-model tests for the engine-switch guard and control-lock predicate.
- No API, persistence, or entitlement changes.
