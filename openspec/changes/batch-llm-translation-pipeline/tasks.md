## 1. Protocol surface and shared models

- [ ] 1.1 Add `struct BatchPageInput { let pageId: String; let bubbles: [BubbleCluster] }` to `MangaTranslator/Services/TranslationService.swift` (or adjacent file). `pageId` is the stable identifier used to map request pages to response pages; production callers use `String(pageIndex)`.
- [ ] 1.2 Add `struct BatchPageOutput { let pageId: String; let bubbles: [TranslatedBubble]; let detectedTerms: [DetectedGlossaryTerm] }` to the same file.
- [ ] 1.3 Add `func translateBatch(pageInputs: [BatchPageInput], from source: Language, to target: Language, priorContext: TranslationContext) async throws -> [BatchPageOutput]` to the `TranslationService` protocol.
- [ ] 1.4 Add a default `extension TranslationService` implementation of `translateBatch` that loops over `pageInputs` in order, calls the existing per-page `translate(...)` for each, returns the assembled outputs, and propagates any thrown error from the first failing call.
- [ ] 1.5 Confirm DeepL, Google, Copilot, and OpenAI services still compile against the new protocol (Copilot and OpenAI override in later sections; DeepL/Google rely on the default extension).

## 2. Multi-page prompt and parser tests first

- [ ] 2.1 Add `testMultiPageUserPromptListsPagesInIndexOrder` to `MangaTranslatorTests/LLMPromptTests.swift` (create file if needed). Given three `BatchPageInput` with page ids "1", "2", "3", assert the user-prompt string contains each page id as a section marker in ascending order and no other page id between them.
- [ ] 2.2 Add `testMultiPageSystemPromptIncludesRecentContextOnceWhenPriorPagesExist`. Given `priorContext` with two recent page summaries, assert the system prompt contains exactly one `## Recent context` block and that block lists the two prior pages in ascending page-index order.
- [ ] 2.3 Add `testMultiPageSystemPromptOmitsRecentContextWhenPriorPagesEmpty`. Given empty `priorContext.recentPageSummaries`, assert the system prompt does not contain `## Recent context`.
- [ ] 2.4 Add `testMultiPageUserPromptDoesNotInjectRecentContextForBatchInternalPages`. Given three batched pages, assert the user prompt does not contain `## Recent context` for any of the three.
- [ ] 2.5 Add `testMultiPageResponseParserMapsByPageId` to `MangaTranslatorTests/LLMResponseParserTests.swift` (create if needed). Given a synthetic response with pages "1", "2", "3" in shuffled order, assert the parser returns `[BatchPageOutput]` in the requested page-id order (or whatever ordering the parser contract specifies — see task 3.4).
- [ ] 2.6 Add `testMultiPageResponseParserRejectsMissingPageId`. Given a synthetic response missing page "2" of a requested set ("1", "2", "3"), assert the parser throws an error type that the scheduler recognizes as "trigger fallback".
- [ ] 2.7 Add `testMultiPageResponseParserRejectsExtraPageId`. Given a synthetic response containing an extra page "9" not in the request, assert the parser throws the same fallback-triggering error type.
- [ ] 2.8 Run the suite, confirm all 2.x tests are red because the multi-page prompt/parser APIs do not exist.

## 3. Multi-page prompt and parser implementation

- [ ] 3.1 Add `LLMPrompt.multiPageUserPrompt(pageInputs: [BatchPageInput]) -> String` that lists each page as a `## Page <pageId>` block followed by the bubbles JSON for that page.
- [ ] 3.2 Reuse the existing `LLMPrompt.systemPrompt(from:to:context:)` signature for the batch path; the batch caller passes `TranslationContext` whose `recentPageSummaries` is the rolling window sampled before the batch. No new system-prompt builder is needed.
- [ ] 3.3 Add `LLMResponseParser.parseMultiPage(_ responseText: String, requestedPageIds: [String]) throws -> [(pageId: String, bubbles: [TranslatedBubble], detectedTerms: [DetectedGlossaryTerm])]` that:
  - Parses the response body as JSON with the multi-page schema.
  - Validates that every `requestedPageIds` element appears in the response and no other page ids appear.
  - Returns the results in the order of `requestedPageIds` (deterministic regardless of response ordering).
- [ ] 3.4 Define a dedicated error case `LLMResponseParser.MultiPageParseError` with sub-cases for `missingPage(id: String)`, `unexpectedPage(id: String)`, `malformedJSON`. The scheduler treats any of these as "trigger fallback".
- [ ] 3.5 Run section 2 tests, confirm all green.

## 4. Provider batch implementation tests first

- [ ] 4.1 Add `testCopilotTranslateBatchSendsMultiPageRequest` to `MangaTranslatorTests/CopilotTranslationServiceTests.swift`. Use a `URLProtocol` stub session; assert the outgoing request body contains the multi-page user prompt and the `## Recent context` block (when prior context provided).
- [ ] 4.2 Add `testCopilotTranslateBatchReturnsOutputsInRequestedOrder`. Stub a valid multi-page response with pages in shuffled order; assert the returned `[BatchPageOutput]` matches the requested order.
- [ ] 4.3 Add `testCopilotTranslateBatchRetriesOnceOnHTTP500`. Stub the first response as HTTP 500 and the second as HTTP 200 with a valid body; assert the method returns successfully and the stub recorded exactly 2 requests.
- [ ] 4.4 Add `testCopilotTranslateBatchThrowsAfterSecondHTTP500`. Stub both responses as HTTP 500; assert the method throws and the stub recorded exactly 2 requests. The thrown error must be one the scheduler can detect as "fallback trigger".
- [ ] 4.5 Add `testCopilotTranslateBatchThrowsOnMissingPageId`. Stub HTTP 200 with a response missing one requested page id (both attempts); assert the thrown error is the parser's missing-page error and the stub recorded exactly 2 requests.
- [ ] 4.6 Mirror tasks 4.1–4.5 for `OpenAITranslationServiceTests` (`testOpenAITranslateBatch*`).
- [ ] 4.7 Run the suite, confirm all 4.x tests are red.

## 5. Provider batch implementation

- [ ] 5.1 Implement `CopilotTranslationService.translateBatch(pageInputs:from:to:priorContext:)`:
  - Build system prompt via `LLMPrompt.systemPrompt(from:to:context: priorContext)`.
  - Build user prompt via `LLMPrompt.multiPageUserPrompt(pageInputs:)`.
  - Issue one POST to `<baseURL>/chat/completions` with existing headers (`Authorization`, `Copilot-Integration-Id: copilot-developer-cli`, `Content-Type`).
  - On HTTP 5xx, transport error, parse error, or `MultiPageParseError`, wait per the exponential backoff schedule (500ms, 2x multiplier on retry) and retry exactly once.
  - On second failure, throw a sanitized error (use the existing `APIErrorSanitizer` machinery).
  - On success, parse via `LLMResponseParser.parseMultiPage` and return `[BatchPageOutput]`.
- [ ] 5.2 Implement `OpenAITranslationService.translateBatch(...)` with the same structure but with OpenAI-compatible headers and endpoint resolution.
- [ ] 5.3 Run section 4 tests, confirm all green.

## 6. View-model batch scheduler tests first

- [ ] 6.1 Add `testRunBatchPipelineGroupsFiveLowBubblePagesIntoOneBatch` to `MangaTranslatorTests/TranslationViewModelTests.swift`. Use a fake `TranslationService` that records every `translateBatch` and `translate` call. Set up 5 miss pages with 8 bubbles each; assert exactly 1 `translateBatch` call and 0 per-page `translate` calls.
- [ ] 6.2 Add `testRunBatchPipelineFlushesOnBubbleThreshold`. Set up 5 miss pages with [20, 20, 5, 5, 5] bubbles; assert two `translateBatch` calls with page sets [1,2] and [3,4,5].
- [ ] 6.3 Add `testRunBatchPipelineFlushesOnPageCap`. Set up 8 miss pages with 4 bubbles each; assert two `translateBatch` calls with page sets [1..5] and [6,7,8].
- [ ] 6.4 Add `testRunBatchPipelineSinglePageOverBubbleThresholdRunsAlone`. Set up 2 miss pages with [60, 10] bubbles; assert two `translateBatch` calls with page sets [1] and [2].
- [ ] 6.5 Add `testRunBatchPipelineCacheHitActsAsBatchBoundary`. Set up 5 pages where page 3 is a cache hit and 1, 2, 4, 5 are misses; assert two `translateBatch` calls with page sets [1,2] and [4,5], and no batch contains page 3.
- [ ] 6.6 Add `testRunBatchPipelineCachedPageContributesToNextBatchRecentContext`. Same setup as 6.5. Assert that the second `translateBatch` call's `priorContext.recentPageSummaries` contains page 3's cached bubble text.
- [ ] 6.7 Add `testRunBatchPipelineBatchFailureFallsBackToPerPageInPageIndexOrder`. Fake service throws on `translateBatch` for the group [3,4,5]; assert the scheduler then calls per-page `translate` for pages 3, 4, 5 in that order.
- [ ] 6.8 Add `testRunBatchPipelineBatchFailureFallbackPreservesRecentContext`. Build on 6.7. After fallback, assert page 4's per-page request observed pages [1,2,3] in `recentPageSummaries`, and page 5's request observed [2,3,4].
- [ ] 6.9 Add `testRunBatchPipelineCancelDuringBatchReturnsBatchPagesToPending`. Start a batch run, cancel via the existing cancel pathway while the fake service is suspended inside `translateBatch`; assert pages in the in-flight batch return to `.pending`, no later batch is invoked, and pages already finalized before the cancel keep their state.
- [ ] 6.10 Add `testRunBatchPipelineDeepLEngineSkipsBatchPath`. Configure the view model with a DeepL engine; assert the scheduler never calls `translateBatch` and uses the existing per-page parallel path.
- [ ] 6.11 Add `testTranslatePageSinglePageEntrySkipsBatchPath`. Call `translatePage(at:bypassCache:)` for one page; assert the scheduler does not enter the batch grouping code and the per-page `translate` is called directly.
- [ ] 6.12 Run the suite, confirm all 6.x tests are red.

## 7. View-model batch scheduler implementation

- [ ] 7.1 In `TranslationViewModel.swift`, define `private struct BatchSizingConfig { static let maxBubbles = 45; static let maxPages = 5 }`.
- [ ] 7.2 Replace the LLM finalize loop inside `runBatchPipeline`'s `usesContext` branch with a scheduler that iterates over `preparations` in page-index order:
  - Maintain a mutable `currentGroup: [(pageIndex: Int, prep: PagePreparation)]`.
  - For each preparation in order:
    - If preparation is `.cacheHit`: flush `currentGroup` via `runBatch(...)`, then call `finalizePage(at:preparation:service:usesRecentContext:true)` to apply the cache hit.
    - Else if preparation is `.failed` or `.missingKey` or `.sameLanguageSkip`: flush `currentGroup`, then call `finalizePage(...)` to apply the failure/skip state. Failed pages do not enter a batch.
    - Else if preparation is `.fresh`: if adding it to `currentGroup` would exceed either `maxBubbles` or `maxPages`, flush `currentGroup` first; then append.
  - After the loop, flush any remaining `currentGroup`.
- [ ] 7.3 Implement `private func runBatch(_ group: [...], service: any TranslationService, usesRecentContext: Bool) async`:
  - If group is empty, return.
  - Build `[BatchPageInput]` from group, using `String(pageIndex)` as `pageId`.
  - Build `priorContext: TranslationContext` from the current rolling window (must use the same builder the per-page path uses to derive `recentPageSummaries`).
  - Call `service.translateBatch(pageInputs:from:to:priorContext:)`.
  - On success, for each `BatchPageOutput`, route through the existing `finalizePage` success arm (write to pages array, append to rolling window via the same helper, write to cache). Use the page-id to look up the original page index.
  - On thrown error from `translateBatch`, log via `DebugLogger` with a `batchFallback` category, then run the existing per-page serial finalize loop for the group's pages exactly as today's `runBatchPipeline` did for those pages.
- [ ] 7.4 Wire cancellation: the existing `runBatchPipeline`'s `Task` cancellation propagates naturally to `service.translateBatch` via Swift Concurrency. When `translateBatch` throws a cancellation error, the scheduler resets the group's pages to `.pending` and exits without starting later batches.
- [ ] 7.5 Confirm `translatePage(at:bypassCache:)` remains unchanged; it does not call into the batch scheduler.
- [ ] 7.6 Confirm the DeepL/Google branch of `runBatchPipeline` (the `else` branch) is unchanged.
- [ ] 7.7 Run section 6 tests, confirm all green.

## 8. End-to-end regression

- [ ] 8.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests` and confirm all tests (existing + new) pass.
- [ ] 8.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/CopilotTranslationServiceTests` and confirm pass.
- [ ] 8.3 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/OpenAITranslationServiceTests` and confirm pass.
- [ ] 8.4 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/LLMPromptTests` (or whatever suite name section 2 settled on) and confirm pass.
- [ ] 8.5 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/LLMResponseParserTests` and confirm pass.
- [ ] 8.6 Run the full `MangaTranslatorTests` suite as smoke and confirm no regression.
- [ ] 8.7 Run `openspec validate batch-llm-translation-pipeline --strict` and confirm valid.

## 9. Manual verification on a real batch

- [ ] 9.1 Open a real manga folder (3–10 pages) in the app with `GitHub Copilot` engine selected and run batch translate. Confirm UI progresses through `.pending → .processing → .translated` for every page and pages translate end-to-end.
- [ ] 9.2 With `OpenAI Compatible` engine selected, repeat 9.1.
- [ ] 9.3 With `DeepL` engine selected, repeat 9.1 and confirm behavior matches the pre-change baseline (no batch path engaged).
- [ ] 9.4 Trigger a batch failure path by temporarily configuring an invalid API token, run batch translate, and confirm the UI surfaces error states for the affected pages without crashing.
- [ ] 9.5 Start a long batch translate and click cancel while a batch is in flight; confirm in-flight batch pages return to `.pending` and remaining pages do not start.
