## 1. Red — pipelining and ramp tests (must fail on the shipped two-phase pipeline)

- [x] 1.1 Test: ramp-up grouping composition — 12 miss pages, 4 bubbles each; assert batch requests [0], [1,2,3], [4..8], [9,10,11] (`testRunBatchPipelineRampUpGroupCapsAndHoldsAtFive`, red: shipped produces 3 batches)
- [x] 1.2 Test: first batch dispatches before later preparations complete (`testFirstLLMBatchDispatchesBeforeLaterPreparationsComplete`, red: shipped observes 4/4 OCR at first translate)
- [x] 1.3 Test: out-of-order preparation does not reorder consumption (`testCacheHitPreparedEarlyIsConsumedInPageOrder`, pinning: green on shipped pipeline as expected)
- [x] 1.4 Relax `testOcrWorkCanStillCompleteBeforeSerialLLMTranslation` to `>= 1` per the archived design note

## 2. Green — pipeline implementation

- [x] 2.1 Strip `image` from the `restoreFrom` snapshot in `preparePage` (capture with `image = nil`; restore path reads only `.state`)
- [x] 2.2 Rework `runBatchPipeline`'s context-consuming branch into the interleaved producer/consumer loop (`runPipelinedLLMBatch`): ordered buffer `[Int: PagePreparation]`, `nextIndex` consumer woven into the `withTaskGroup` producer loop
- [x] 2.3 Implement ramp-up group accumulation (`rampPageCap`): caps 1, 3, 5...; dispatch on ramp cap, 45-bubble cut, cache-hit/skip/failure boundary, or list exhaustion; boundaries do not consume ramp slots
- [x] 2.4 Route non-ready preparations through the existing per-page `finalizePage` in consumption order, acting as group boundaries
- [x] 2.5 Updated 10 existing tests to ramp compositions: glossary-from-any-page (3 pages), five-low-bubble (renamed `...UnderRampCaps`), bubble-threshold, page-cap, cache-hit boundary ×2, fallback ×2 (fail group [1,2,3]), recent-context-in-page-order, retranslate-all
- [x] 2.6 New red tests green; ordering-invariant tests (failure skipping, single-over-45, cache-hit contribution, non-context engines, OCR concurrency cap) pass unmodified

## 3. Cancellation

- [x] 3.1 Test: cancel reverts pages still in preparation (`testRunBatchPipelineCancelRevertsPagesStillInPreparation`, delayed OCR keeps preparations in flight at the cancel point)
- [x] 3.2 Post-quiescence revert sweep implemented in `runPipelinedLLMBatch` (cancelAll + drain, then revert every `.processing` page to `.pending`)
- [x] 3.3 Existing cancellation tests (mid-batch revert, late-cancel-before-persist, no-fallback-on-cancel) pass unmodified

## 4. Verification and docs

- [x] 4.1 Full MangaTranslator scheme test suite: TEST SUCCEEDED (2026-06-13)
- [x] 4.2 Manual smoke test: 20+ page folder with an LLM engine — first page readable after roughly one page's OCR plus one small LLM round-trip; memory stays flat (sliding image window unaffected)
- [x] 4.3 `openspec validate producer-consumer-llm-pipeline --strict` passes; sync delta into `openspec/specs/contextual-translation/spec.md` at archive time
