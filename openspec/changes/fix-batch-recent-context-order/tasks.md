## 1. Tests First

- [x] 1.1 Add `llmBatchTranslationBuildsRecentContextInPageOrder` in `MangaTranslatorTests/TranslationViewModelTests.swift`: create 4 pages with deterministic OCR text, use a fake `.githubCopilot` or `.openAI` translation service that records contexts and uses delays that would expose completion-order bugs, then assert page 3 receives pages 1 and 2 in page-index order and page 4 receives pages 1, 2, and 3 in page-index order.
- [x] 1.2 Add `nonContextualEnginesDoNotReceiveRecentPageContext`: use a fake `.deepL` or `.google` translation service, translate multiple pages with an active glossary, and assert every request has empty `recentPageSummaries` while `glossaryTerms` is still populated.
- [x] 1.3 Add `ocrWorkCanStillCompleteBeforeSerialLLMTranslation`: use fake OCR instrumentation to show OCR/page preparation can start before lower-index LLM translation finishes, while fake LLM translation calls start in ascending page-index order with no overlap for context-consuming engines.
- [x] 1.4 Add `llmBatchCacheHitsContributeToLaterRecentContextWithoutRetranslating`: prepopulate cache for page 1, run a 2-page LLM batch, assert page 1 does not call the translation service, and assert page 2 receives page 1's cached translated text in `recentPageSummaries`.
- [x] 1.5 Add `llmBatchSkipsFailedPagesInLaterRecentContext`: make page 1 fail during OCR or translation and page 2 succeed, then assert page 2 is translated and its context excludes page 1.
- [x] 1.6 Add `retranslateAllPagesUsesPageOrderedRecentContextForLLMEngines`: call `retranslateAllPages()` and assert it follows the same page-index context order as initial batch translation.
- [x] 1.7 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests` and confirm the new tests fail for the current implementation before production changes.

## 2. Implement Context-Aware Batch Pipeline

- [x] 2.1 Read `TranslationViewModel.translateBatch()`, `retranslateAllPages()`, `translatePage(at:bypassCache:)`, `buildTranslationContext()`, `appendToRecentContext(_:)`, and translation service engine selection before editing.
- [x] 2.2 Add an explicit recent-context predicate for translation engines, with `.openAI` and `.githubCopilot` returning true and `.deepL` and `.google` returning false.
- [x] 2.3 Refactor batch processing so OCR, image loading, image hash computation, cache lookup, and meaningless-bubble filtering can run with bounded concurrency without consuming or mutating recent-page context.
- [x] 2.4 For context-consuming LLM engines, finalize translation in ascending page-index order and build context from active glossary terms plus the current page-ordered rolling recent-context window.
- [x] 2.5 For DeepL and Google, pass glossary terms with empty `recentPageSummaries`, and do not read or write `recentPageTranslations`.
- [x] 2.6 Ensure cache-hit pages set page state from cached data and append their cached translated text to the LLM batch recent-context window without calling OCR or translation.
- [x] 2.7 Ensure failed pages set page-local error state, contribute nothing to recent context, and do not prevent later pages from completing when those pages succeed.
- [x] 2.8 Make `translateBatch()` and `retranslateAllPages()` use the same batch pipeline, with the intended cache policy difference: initial batch may read cache, re-translate-all bypasses cache and overwrites cache.
- [x] 2.9 Keep single-page `translatePage(at:bypassCache:)` usable and aligned with the same engine boundary: LLM engines may use recent summaries, while DeepL/Google receive only glossary context.

## 3. Verification

- [x] 3.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests`.
- [x] 3.2 Run any narrower related tests added for helper types if the implementation extracts a new testable coordinator.
- [x] 3.3 Run `openspec validate fix-batch-recent-context-order --strict`.

## 4. PLAN.md Sync

- [x] 4.1 Update `PLAN.md` Task 2 to reference `openspec/changes/fix-batch-recent-context-order` as the source of truth.
- [x] 4.2 Keep `PLAN.md` as an execution checklist only; remove or shorten any Task 2 wording that duplicates the OpenSpec requirements and could drift.
