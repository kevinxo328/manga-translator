## 1. Protocol surface and shared models

- [x] 1.1 Add `struct BatchPageInput { let pageId: String; let bubbles: [BubbleCluster] }` to `MangaTranslator/Models/Models.swift` (where `TranslationService` currently lives) or an adjacent service-model file. `pageId` is the stable identifier used to map request pages to response pages; production callers use `String(pageIndex)`.
- [x] 1.2 Add `struct BatchPageOutput { let pageId: String; let bubbles: [TranslatedBubble]; let detectedTerms: [GlossaryTerm] }` to the same file. (Uses existing `GlossaryTerm` instead of the task's non-existent `DetectedGlossaryTerm`; matches `TranslationOutput.detectedTerms` and `glossaryService.insertDetectedTerms`.)
- [x] 1.3 Add `func translateBatch(pageInputs: [BatchPageInput], from source: Language, to target: Language, priorContext: TranslationContext) async throws -> [BatchPageOutput]` to the `TranslationService` protocol.
- [x] 1.4 Add a default `extension TranslationService` implementation of `translateBatch` that loops over `pageInputs` in order, calls the existing per-page `translate(...)` for each, returns the assembled outputs, and propagates any thrown error from the first failing call.
- [x] 1.5 Confirm DeepL, Google, Copilot, and OpenAI services still compile against the new protocol (Copilot and OpenAI override in later sections; DeepL/Google rely on the default extension).

## 2. Multi-page prompt and parser tests first

- [x] 2.1 Add `testMultiPageUserPromptListsPagesInIndexOrder` to `MangaTranslatorTests/LLMPromptTests.swift` (create file if needed). Given three `BatchPageInput` with page ids "1", "2", "3", assert the user-prompt string contains each page id as a section marker in ascending order and no other page id between them.
- [x] 2.2 Add `testMultiPageSystemPromptIncludesRecentContextOnceWhenPriorPagesExist`. Given `priorContext` with two recent page summaries, assert the batch system prompt contains exactly one `## Recent context` block, that block lists the two prior pages in ascending page-index order, and the prompt instructs the model to return the multi-page `{"pages":[...]}` response object.
- [x] 2.3 Add `testMultiPageSystemPromptOmitsRecentContextWhenPriorPagesEmpty`. Given empty `priorContext.recentPageSummaries`, assert the batch system prompt does not contain `## Recent context`.
- [x] 2.4 Add `testMultiPageUserPromptDoesNotInjectRecentContextForBatchInternalPages`. Given three batched pages, assert the user prompt does not contain `## Recent context` for any of the three.
- [x] 2.5 Add `testMultiPageResponseParserMapsByPageId` to `MangaTranslatorTests/LLMResponseParserTests.swift` (create if needed). Given a synthetic response with pages "1", "2", "3" in shuffled order, assert the parser returns `[BatchPageOutput]` in the requested page-id order (or whatever ordering the parser contract specifies — see task 3.4).
- [x] 2.6 Add `testMultiPageResponseParserRejectsMissingPageId`. Given a synthetic response missing page "2" of a requested set ("1", "2", "3"), assert the parser throws an error type that the scheduler recognizes as "trigger fallback".
- [x] 2.7 Add `testMultiPageResponseParserRejectsExtraPageId`. Given a synthetic response containing an extra page "9" not in the request, assert the parser throws the same fallback-triggering error type.
- [x] 2.8 Run the suite, confirm all 2.x tests are red because the multi-page prompt/parser APIs do not exist. (Hook blocks intentional red builds; section 3 implementation followed immediately and tests went green together.)

## 3. Multi-page prompt and parser implementation

- [x] 3.1 Add `LLMPrompt.multiPageUserPrompt(pageInputs: [BatchPageInput]) -> String` that emits the dedicated multi-page request JSON object `{"pages":[{"page_id":"...","bubbles":[...]}]}` with pages in requested order.
- [x] 3.2 Add `LLMPrompt.multiPageSystemPrompt(from:to:context:) -> String` for the batch path. It may share common rule text with the per-page prompt, but its response instruction must require only the multi-page `{"pages":[...]}` response object and must not reuse the per-page flat-array response instruction.
- [x] 3.3 Add `LLMResponseParser.parseMultiPage(_ responseText: String, pageInputs: [BatchPageInput]) throws -> [BatchPageOutput]` that:
  - Parses the response body as JSON with the multi-page schema.
  - Validates that every requested page id appears in the response and no other page ids appear.
  - Returns the results in the order of `pageInputs.map { $0.pageId }` (deterministic regardless of response ordering).
  - Signature deviates from task: parser receives full `[BatchPageInput]` (not bare ids) so it can rebuild `TranslatedBubble` per page; matches the per-page `parse(_:bubbles:)` shape.
- [x] 3.4 Define a dedicated error case `LLMResponseParser.MultiPageParseError` with sub-cases for `missingPage(id: String)`, `unexpectedPage(id: String)`, `malformedJSON`. The scheduler treats any of these as "trigger fallback".
- [x] 3.5 Run section 2 tests, confirm all green.

## 4. Provider batch implementation tests first

- [x] 4.1 Add `testCopilotTranslateBatchSendsMultiPageRequest` to `MangaTranslatorTests/CopilotTranslationServiceTests.swift`. Use a `URLProtocol` stub session; assert the outgoing request body contains the multi-page user prompt and the `## Recent context` block (when prior context provided).
- [x] 4.2 Add `testCopilotTranslateBatchReturnsOutputsInRequestedOrder`. Stub a valid multi-page response with pages in shuffled order; assert the returned `[BatchPageOutput]` matches the requested order.
- [x] 4.3 Add `testCopilotTranslateBatchRetriesOnceOnHTTP500`. Stub the first response as HTTP 500 and the second as HTTP 200 with a valid body; assert the method returns successfully and the stub recorded exactly 2 requests.
- [x] 4.4 Add `testCopilotTranslateBatchThrowsAfterSecondHTTP500`. Stub both responses as HTTP 500; assert the method throws and the stub recorded exactly 2 requests. The thrown error must be one the scheduler can detect as "fallback trigger".
- [x] 4.5 Add `testCopilotTranslateBatchThrowsOnMissingPageId`. Stub HTTP 200 with a response missing one requested page id (both attempts); assert the thrown error is the parser's missing-page error and the stub recorded exactly 2 requests.
- [x] 4.6 Add `testCopilotTranslateBatchDoesNotRetryOrFallbackOnCancellation`. Stub or fake a cancellation error (`CancellationError` or `URLError.cancelled`) and assert the method propagates cancellation after exactly 1 request with no retry.
- [x] 4.7 Mirror tasks 4.1–4.6 for `OpenAITranslationServiceTests` (`testOpenAITranslateBatch*`).
- [x] 4.8 Run the suite, confirm all 4.x tests are red. (Hook blocks red builds; section 5 implementation followed immediately and all 12 tests went green together.)
- [x] 4.9 Extend `ProviderHTTPMockURLProtocol` with a Result-returning handler overload so tests can inject transport-level errors (e.g. `URLError(.cancelled)`) alongside synthetic HTTP responses, and add `URLRequest.readMockBody()` that drains `httpBodyStream` for outgoing-body assertions. Both helpers are required by 4.1 (body inspection) and 4.6 (cancellation injection) and were not present in the existing mock infrastructure.

## 5. Provider batch implementation

- [x] 5.1 Implement `CopilotTranslationService.translateBatch(pageInputs:from:to:priorContext:)`:
  - Build system prompt via `LLMPrompt.multiPageSystemPrompt(from:to:context: priorContext)`.
  - Build user prompt via `LLMPrompt.multiPageUserPrompt(pageInputs:)`.
  - Issue one POST to `<baseURL>/chat/completions` with existing headers (`Authorization`, `Copilot-Integration-Id: copilot-developer-cli`, `Content-Type`).
  - On HTTP 5xx, non-cancellation transport error, parse error, or `MultiPageParseError`, wait per the exponential backoff schedule (500ms, 2x multiplier on retry) and retry exactly once.
  - On user cancellation (`CancellationError`, `URLError.cancelled`, or a service-level cancellation wrapper), propagate cancellation immediately without retry, sanitization, or per-page fallback.
  - On second failure, throw a sanitized error (use the existing `APIErrorSanitizer` machinery).
  - On success, parse via `LLMResponseParser.parseMultiPage` and return `[BatchPageOutput]`.
  - The protocol entry above checks `CopilotEnvironment.check()` for the token, then delegates to an internal `translateBatch(..., token:)` overload that owns the retry/parse/cancellation loop. Tests drive the internal overload directly the same way the existing error tests drive `callAPI` — keeps the protocol contract clean while letting tests bypass the env check.
- [x] 5.2 Implement `OpenAITranslationService.translateBatch(...)` with the same structure but with OpenAI-compatible headers and endpoint resolution. (OpenAI already exposes the keychain via init, so no token-bearing overload is needed; tests inject `KeychainService.mocked(returning:)` instead.)
- [x] 5.3 Run section 4 tests, confirm all green.

## 6. View-model batch scheduler tests first

- [x] 6.1 Add `testRunBatchPipelineGroupsFiveLowBubblePagesIntoOneBatch` to `MangaTranslatorTests/TranslationViewModelTests.swift`. Use a fake `TranslationService` that records every `translateBatch` and `translate` call. Set up 5 miss pages with 8 bubbles each; assert exactly 1 `translateBatch` call and 0 per-page `translate` calls.
- [x] 6.2 Add `testRunBatchPipelineFlushesOnBubbleThreshold`. Spec-aligned with [20, 20, 20, 5, 5] (task originally listed [20,20,5,5,5] which under "≤45" would group as [1,2,3]+[4,5], contradicting the spec scenario "[1,2] then [3,4,5]"). Asserts two `translateBatch` calls with page sets [0,1] and [2,3,4].
- [x] 6.3 Add `testRunBatchPipelineFlushesOnPageCap`. Set up 8 miss pages with 4 bubbles each; assert two `translateBatch` calls with page sets [0..4] and [5,6,7].
- [x] 6.4 Add `testRunBatchPipelineSinglePageOverBubbleThresholdRunsAlone`. Set up 2 miss pages with [60, 10] bubbles; assert two `translateBatch` calls with page sets [0] and [1].
- [x] 6.5 Add `testRunBatchPipelineCacheHitActsAsBatchBoundary`. Pre-populates the cache for page index 2 (third page); asserts two `translateBatch` calls with page sets [0,1] and [3,4], and no batch contains page 2.
- [x] 6.6 Add `testRunBatchPipelineCachedPageContributesToNextBatchRecentContext`. Same setup as 6.5. Asserts that the second `translateBatch` call's `priorContext.recentPageSummaries` contains page 2's cached bubble text.
- [x] 6.7 Add `testRunBatchPipelineBatchFailureFallsBackToPerPageInPageIndexOrder`. Fake service throws on `translateBatch` for the second group [3,4]; asserts the scheduler then calls per-page `translate` for pages 3, 4 in that order. (Group sizing differs from task wording due to bubble-count fixture.)
- [x] 6.8 Add `testRunBatchPipelineBatchFailureFallbackPreservesRecentContext`. Builds on 6.7. Asserts page 3's per-page request sees 3 summaries from successful prior pages and page 4's window shifts after page 3 succeeds.
- [x] 6.9 Add `testRunBatchPipelineCancelDuringBatchReturnsBatchPagesToPending`. Cancels while fake service is suspended inside `translateBatch`; asserts pages return to `.pending` and no later batch fires.
- [x] 6.10 Add `testRunBatchPipelineCancelDuringBatchDoesNotFallbackToPerPage`. Cancels mid-batch; asserts no per-page `translate` calls for the cancelled group.
- [x] 6.11 Add `testRunBatchPipelineDeepLEngineSkipsBatchPath`. DeepL engine; asserts no `translateBatch` calls and per-page parallel path runs.
- [x] 6.12 Add `testTranslatePageSinglePageEntrySkipsBatchPath`. `translatePage(at:bypassCache:)`; asserts no `translateBatch` call and one `translate` call.
- [x] 6.13 Run the suite, confirm all 6.x tests are red. (Hook blocks intentional red builds; section 7 implementation landed alongside and all 12 tests went green together.)

## 7. View-model batch scheduler implementation

- [x] 7.1 In `TranslationViewModel.swift`, define `private struct BatchSizingConfig { static let maxBubbles = 45; static let maxPages = 5 }`.
- [x] 7.2 Replace the LLM finalize loop inside `runBatchPipeline`'s `usesContext` branch with a scheduler that iterates over `preparations` in page-index order. Treats `.ready` as batch-eligible (the codebase uses `.ready` for the "fresh" case named in this task); `.cacheHit`, `.noMeaningfulBubbles`, `.failed`, `.missingKey`, `.sameLanguageSkip` all flush the current group then finalize directly.
- [x] 7.3 Implement `private func runBatch(_ group: [BatchPlanItem], service: any TranslationService) async -> Bool`. Returns `true` when the run was cancelled so the outer loop stops. On non-cancellation failure, falls back via `finalizePage(at:preparation:.ready(...), service:, usesRecentContext:true)` for each page in page-index order, reusing the existing finalize success arm. Logs through `pipelineLogger` with `operation: batchFallback` metadata.
- [x] 7.4 Wire cancellation: `URLError.cancelled` and `CancellationError` from `translateBatch` revert the batch's pages to `.pending` and exit without retry or per-page fallback.
- [x] 7.5 Confirm `translatePage(at:bypassCache:)` remains unchanged; verified by `testTranslatePageSinglePageEntrySkipsBatchPath`.
- [x] 7.6 Confirm the DeepL/Google branch of `runBatchPipeline` (the `else` branch) is unchanged.
- [x] 7.7 Run section 6 tests, confirm all green.
- [x] 7.8 Update the two pre-existing LLM-batch tests whose assertions encoded the old per-page rolling-context contract (called out in design.md Risks):
  - `testLLMBatchTranslationBuildsRecentContextInPageOrder`: now uses 6 pages so the run spans two batches; asserts batch-1 (pages 0..4) shares an empty priorContext and batch-2 (page 5) sees the rolling window after batch 1 trimmed to the last 3.
  - `testRetranslateAllPagesUsesPageOrderedRecentContextForLLMEngines`: same 6-page extension applied to the retranslate path.
  - No other existing tests required updates; tests asserting "every page is translated exactly once" (`callOrderInputs`, `maxConcurrentTranslations`, cache-hit/failed-page-context) continue to pass because the `TranslationService` default extension delegates to per-page `translate(...)` in order.

## 8. End-to-end regression

- [x] 8.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests` and confirm all tests (existing + new) pass.
- [x] 8.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/CopilotTranslationServiceTests` and confirm pass.
- [x] 8.3 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/OpenAITranslationServiceTests` and confirm pass.
- [x] 8.4 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/LLMPromptTests` (suite name unchanged; added `LLMPromptMultiPageTests` and `BatchSchedulerTests` siblings) and confirm pass.
- [x] 8.5 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/LLMResponseParserTests` and confirm pass.
- [x] 8.6 Run the full `MangaTranslatorTests` suite as smoke and confirm no regression. `** TEST SUCCEEDED **`.
- [x] 8.7 Run `openspec validate batch-llm-translation-pipeline --strict` and confirm valid. (`Change 'batch-llm-translation-pipeline' is valid`)

## 9. Manual verification on a real batch

- [x] 9.1 Open a real manga folder (3–10 pages) in the app with `GitHub Copilot` engine selected and run batch translate. Confirm UI progresses through `.pending → .processing → .translated` for every page and pages translate end-to-end.
- [x] 9.2 With `OpenAI Compatible` engine selected, repeat 9.1.
- [x] 9.3 With `DeepL` engine selected, repeat 9.1 and confirm behavior matches the pre-change baseline (no batch path engaged).
- [x] 9.4 Trigger a batch failure path by temporarily configuring an invalid API token, run batch translate, and confirm the UI surfaces error states for the affected pages without crashing.
- [x] 9.5 Start a long batch translate and click cancel while a batch is in flight; confirm in-flight batch pages return to `.pending` and remaining pages do not start.
