## 1. Lock predicate + view-model guard (TDD)

- [ ] 1.1 Write failing tests for `isTranslationInFlight`: true while `isProcessing` is true; true while any page's state is `.processing` (batch flag false); false when no batch is running and no page is `.processing`
- [ ] 1.2 Write failing tests: `switchEngineForCurrentPage()` returns without mutating page state, calling OCR, the translation service, or the cache when `isTranslationInFlight == true` (cover both the batch case and the single-page `.processing` case); and behaves normally when translation is not in flight (existing behavior unchanged)
- [ ] 1.3 Implement the `isTranslationInFlight` computed property on `TranslationViewModel` (per design.md D1) and the early-return guard at the top of `switchEngineForCurrentPage()`, with a comment referencing design.md D2/D3 (Settings-window path is why the guard lives in the view model)
- [ ] 1.4 Run the new tests and confirm green

## 2. Toolbar lock (ContentView)

- [ ] 2.1 Add `.disabled(viewModel.isTranslationInFlight || isEditing)` to the Open toolbar item (keep the existing `isEditing` guard inside the action closure)
- [ ] 2.2 Add `.disabled(viewModel.isTranslationInFlight)` to the glossary picker toolbar item
- [ ] 2.3 Add `.disabled(viewModel.isTranslationInFlight)` to the language-pair toolbar item (both source and target menus)
- [ ] 2.4 Add `.disabled(viewModel.isTranslationInFlight)` to the engine picker toolbar item
- [ ] 2.5 Change Re-translate All gating from `viewModel.isProcessing || isEditing` to `viewModel.isTranslationInFlight || isEditing`

## 3. Sidebar lock (wiring in ContentView)

- [ ] 3.1 Change the `TranslationSidebar` wiring from `isProcessing: viewModel.isCurrentPageProcessing` to `isProcessing: viewModel.isProcessing || viewModel.isCurrentPageProcessing` so the sidebar Re-translate and Edit buttons disable during batch (per design.md D1, the sidebar intentionally does NOT use `isTranslationInFlight`)
- [ ] 3.2 Confirm `TranslationSidebar` itself needs no change (its existing `isProcessing` parameter already gates both buttons)

## 4. Verification

- [ ] 4.1 Run the main test suite (`xcodebuild test -scheme MangaTranslator -destination 'platform=macOS'`) and confirm green
- [ ] 4.2 Manual check (batch): start a multi-page batch and confirm Open, glossary, language, engine, Re-translate All, sidebar Re-translate, and Edit are all disabled while page navigation still works; confirm everything re-enables when the batch finishes
- [ ] 4.3 Manual check (single-page): open a single image (or press sidebar Re-translate on one page) and confirm the toolbar glossary/language/engine pickers, Open, and Re-translate All are disabled while that page is `.processing`, and re-enable when it completes
- [ ] 4.4 Manual check (Settings path): change the engine in the Settings window mid-translation and confirm no per-page switch fires (no spinner churn) and the new engine applies to translations started afterwards
- [ ] 4.5 Manual check (edit → batch direction): open an Edit Mode session and confirm Re-translate All and Open are disabled and dropped files are ignored (existing `isEditing` gating, now spec-pinned — regression check only)
- [ ] 4.6 Run `openspec validate lock-controls-during-batch --strict` and fix any findings
