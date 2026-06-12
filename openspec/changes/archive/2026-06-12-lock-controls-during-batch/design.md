## Context

Batch translation (`runBatchPipeline`) is the only code path that sets `TranslationViewModel.isProcessing`. While it runs, the toolbar disables only the "Re-translate All" button (`ContentView.swift`, `.disabled(viewModel.isProcessing || isEditing)`). All other pipeline-affecting controls remain interactive:

- The engine picker carries an `onChange(of: preferences.translationEngine)` that calls `switchEngineForCurrentPage()` — a single-page translation flow that mutates `pages[index].state` concurrently with the batch pipeline.
- `preparePage` reads `preferences.sourceLanguage`/`targetLanguage` and the active glossary live, per page, so mid-batch changes split the book across two settings configurations and two cache-key families.
- `TranslationSidebar` receives `isProcessing: viewModel.isCurrentPageProcessing` (current page only). During batch, a page that already reached `.translated` re-enables the sidebar Re-translate and Edit buttons even though the global pipeline is still running (and, in Re-translate All mode, may still rewrite that page).
- The Open button can replace `pages` underneath the running pipeline.

The Settings window binds the same `PreferencesService` (`SettingsView.swift` has its own source/target/engine pickers), so toolbar disabling alone cannot fully prevent mid-batch preference changes.

Single-page translation flows have the same exposure: `translatePage` (initial single image, sidebar Re-translate via `retranslateCurrentPage`, engine switch via `switchEngineForCurrentPage`) and the Edit Mode commit path never touch `isProcessing` — they only move the page itself through `.processing`. They read the same live preferences mid-flight, so gating the toolbar on `isProcessing` alone would leave the single-page window open.

## Goals / Non-Goals

**Goals:**

- No pipeline-affecting control in the main window is interactive while any translation is in flight — batch (`isProcessing`) or single-page (any page in `.processing`).
- The engine-switch handler never races an in-flight translation, regardless of where the preference change originated (toolbar or Settings window).
- Reuse existing state; no new published properties (derived predicates only).

**Non-Goals:**

- Locking or snapshotting Settings-window pickers (see Deferred below).
- Cancelling or queueing user actions for replay after the batch finishes.
- A batch progress / cancel UI (existing cancellation semantics are untouched).
- Splitting the `.processing` page state into OCR/translating phases (separate change).

## Decisions

### D1: Gate on a derived `isTranslationInFlight` predicate — no new published state

The lock has two sources, so the view model exposes one computed property combining them:

```swift
var isTranslationInFlight: Bool {
    isProcessing || pages.contains { if case .processing = $0.state { return true } else { return false } }
}
```

`isProcessing` covers the batch pipeline (its exclusive writer is `runBatchPipeline`); the page scan covers single-page flows (initial single image, sidebar Re-translate, engine switch, Edit Mode commit), which mark only the page itself `.processing`. Both inputs are already `@Published`, so the computed property is reactive without new published state.

Gating:

- Toolbar: add `.disabled(viewModel.isTranslationInFlight || isEditing)` (or without `isEditing` where edit-gating is not relevant) to the Open, glossary, language-pair, engine, and Re-translate All toolbar items. SwiftUI `Menu`/`Picker` toolbar items accept `.disabled` directly; the pickers grey out as a unit. Re-translate All and Open get the broader predicate too — starting a batch or replacing `pages` while a single-page flow is in flight is the same race as mid-batch.
- Sidebar: change the wiring in `ContentView` from `isProcessing: viewModel.isCurrentPageProcessing` to `isProcessing: viewModel.isProcessing || viewModel.isCurrentPageProcessing`. `TranslationSidebar` itself is unchanged — its existing `isProcessing` parameter already disables Re-translate and Edit. The sidebar deliberately does **not** use `isTranslationInFlight`: a single-page flow on page N must not lock Re-translate/Edit on page M (that concurrency is allowed today and touches disjoint pages); the batch flag plus the current page's own state is exactly the hazard set.

Edit Mode and batch are mutually exclusive in both directions, which is what makes the per-page sidebar gating safe. Batch → edit: the `isProcessing` term above disables Edit for the entire batch, including `.translated` pages the retranslate-all pass has not reached yet — otherwise an edit session opened on such a page would be stomped by `preparePage` when its turn came. Edit → batch: Re-translate All, Open, and the drag-and-drop handler are already inert while `isEditing` (existing behavior, now pinned by the batch-processing delta spec), so a batch can never start and later collide with an open session. Single-page flows on other pages are the only concurrency left, and they never visit the edited page.

Side effects to accept: cache-hit pages pass through `.processing` briefly, so the toolbar may flicker disabled for a moment on cache-served single-page actions. And the sidebar Re-translate button renders a spinner whenever its `isProcessing` parameter is true, so during batch it now spins for the whole run even when the current page is already translated — a truthful "translation running" signal. Both harmless.

Trade-off noted: a page stuck in `.processing` (e.g. hung network call) locks the toolbar until it resolves to `.translated`/`.error`. Translation calls have timeouts, so the lock always clears; this is preferable to allowing mid-flight settings mutation.

### D2: Guard the engine-switch handler in the view model, not only the UI

`switchEngineForCurrentPage()` gets an early return when `isTranslationInFlight == true`. Disabling the toolbar picker is necessary but not sufficient because the Settings window mutates the same `preferences.translationEngine` and the `onChange` in `ContentView` fires regardless of source. The guard lives in the view-model method (not the `onChange` closure) so every present and future call site is covered and the rule is unit-testable without UI.

The ignored switch is intentionally not replayed after the batch (see Risks).

### D3: Defer Settings-window language/glossary locking

After D2, the remaining Settings-window exposure is: changing source/target language mid-batch makes later-prepared pages use the new pair (consistent per page, never corrupting state — each page's cache entry is keyed by the settings it was actually translated with). This is a quality wart, not a race.

Closing it would require either disabling Settings pickers from translation state (couples the Settings window to pipeline state) or snapshotting the language pair at batch start and threading it through `preparePage` (touches the whole preparation path). Both cost more than the residual risk justifies, given the main-window pickers — the normal path — are locked. Deferred; revisit if users report mixed-language batches via the Settings window. Reference this section from the `switchEngineForCurrentPage()` guard comment.

## Risks / Trade-offs

- [Engine change from Settings mid-batch is silently ignored for the current page] → The preference itself still updates, so the *next* translation uses the new engine — matching the `settings-management` "applies to next translation" requirement. Only the immediate per-page switch behavior is suppressed. Acceptable; no replay queue.
- [User feels locked out during a long batch] → Page navigation and viewing remain fully enabled; only mutating controls are disabled, consistent with the existing disabled "Re-translate All" button.
- [`isProcessing` could later be set by non-batch flows, over-locking the UI] → It is currently set only by `runBatchPipeline`; the delta spec pins this meaning ("while batch translation is running") so any future broadening shows up as a spec violation.

## Migration Plan

Pure UI/view-model gating; no data, cache, or persistence changes. Single PR, no rollback concerns beyond reverting the commit.

## Open Questions

None.
