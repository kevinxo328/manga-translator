## 1. Mode enum refactor (behavior-preserving)

- [ ] 1.1 Introduce `PageTranslationMode` enum (`.standard`, `.retranslate`, `.engineSwitch`) in `TranslationViewModel`; change `translatePage(at:bypassCache:)` and `preparePage(at:bypassCache:service:)` to take `mode:`, mapping `.standard` to today's `bypassCache: false` and `.retranslate` to `bypassCache: true` (`.engineSwitch` not yet wired)
- [ ] 1.2 Update `runBatchPipeline`, `retranslateCurrentPage()`, `retranslateAllPages()`, and the initial-translation call sites to pass the equivalent mode; run the `MangaTranslator` scheme tests and confirm the full suite passes unchanged

## 2. Layout-match predicate

- [ ] 2.1 Write failing tests for the layout-match predicate: matching sets (same count, `boundingBox`, source `text`, `index`; differing translated text still matches), and mismatches for added bubble, deleted bubble, moved `boundingBox`, reordered `index`, and differing source `text`
- [ ] 2.2 Implement the predicate as a pure helper comparing two `[TranslatedBubble]` sequences sorted by `index` (exact `CGRect` equality, no tolerance, per design D2); make the tests pass

## 3. Engine-switch preparation path

- [ ] 3.1 Write failing tests for `.engineSwitch` on a committed page: cache hit with matching layout → `.cacheHit`, no `OCRRouter.processPage` call, no translation-service call, no cache write (scenario: Engine switch hits matching cache without API call)
- [ ] 3.2 Write failing tests for `.engineSwitch` cache miss → committed bubbles preserved verbatim (`boundingBox`, `text`, `index`), no OCR call, translation called once, result written to the new engine's cache (scenario: Engine switch with cache miss preserves bubbles and translates only)
- [ ] 3.3 Write failing tests for stale-cache mismatch: cache hit whose layout lacks a drawn `isManual` bubble, and a reorder-only hit with stale `index` values → cached entry ignored, committed set preserved and re-translated (scenarios: manual edits / reorder-only edit ignores stale cache)
- [ ] 3.4 Write failing tests for the fallback and failure paths: `.engineSwitch` on a page without a committed non-empty bubble set behaves as `.standard` (cache lookup, full OCR on miss), and a translation failure during engine switch restores the previous `.translated` state via `restoreFrom`
- [ ] 3.5 Implement the `.engineSwitch` branch in `preparePage`: conditional cache lookup + layout match, preserve-and-translate on miss/mismatch, `.standard` fallback for non-committed pages, `restoreFrom` populated as in `.retranslate` (design D2–D4); make all group-3 tests pass

## 4. UI wiring

- [ ] 4.1 Add `switchEngineForCurrentPage()` to `TranslationViewModel` calling `translatePage(at: currentPageIndex, mode: .engineSwitch)`; point the `.onChange(of: translationEngine)` handler in `ContentView` at it (keep the `!isEditing` guard); verify `retranslateCurrentPage()` / `retranslateAllPages()` still use `.retranslate`
- [ ] 4.2 Manual verification: translate a page with engine A, switch to B (API call, miss path), switch back to A and confirm instant cached result with no API call (watch the pipeline debug log)

## 5. Spec sync and wrap-up

- [ ] 5.1 Run the full `MangaTranslator` scheme test suite and `openspec validate engine-switch-cache-reuse --strict`; confirm both pass
- [ ] 5.2 Sync the delta spec into `openspec/specs/retranslate/spec.md` (via `/opsx:sync` or archive flow) and mark B1 as done in `SUGGESTION.md`
