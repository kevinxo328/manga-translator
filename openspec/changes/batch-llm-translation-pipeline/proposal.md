## Why

Since the v1.4.6 → main change `fix-batch-recent-context-order`, the batch translation pipeline for context-consuming LLM engines (GitHub Copilot, OpenAI Compatible) finalizes pages strictly one-by-one in page-index order. This makes page 1's translation API call wait for every page's OCR to finish, and removes all concurrency between translation API calls. End-to-end batch latency for an N-page job on LLM engines regressed from roughly `OCR/3 + (API/3) * N` (v1.4.6) to `OCR + API * N` (main). Users report that batch translation is noticeably slower than v1.4.6 while OCR-only batches and DeepL/Google batches feel unchanged. We want to recover the LLM throughput without giving back the deterministic recent-context ordering that `fix-batch-recent-context-order` enforced.

## What Changes

- Add a multi-page LLM batching path in `TranslationViewModel.runBatchPipeline`'s Phase B for context-consuming engines. Up to 5 consecutive miss pages whose total bubble count is at most 45 are grouped into a single LLM API request.
- Add `translateBatch(pageInputs:from:to:priorContext:)` to the `TranslationService` protocol. The default implementation falls back to calling per-page `translate(...)` sequentially so engines that do not implement the batch path retain today's behavior.
- Implement the batch method on `CopilotTranslationService` and `OpenAITranslationService` using a dedicated multi-page JSON schema (request: ordered array of pages each with a stable id and their bubbles; response: `{"pages":[{"page_id":"...","bubbles":[...],"detected_terms":[...]}]}` mapped back by page id).
- Extend `LLMPrompt` to build a multi-page user prompt that lists pages in page-index order, and inject the rolling `Recent context` summary once per batch (covering up to 3 successful pages whose index is strictly less than the batch's first page).
- Extend `LLMResponseParser` to parse a multi-page response and validate that every requested page id appears in the response; missing or malformed pages trigger the documented fallback.
- On batch failure (HTTP non-2xx, transport error, parse failure, missing page in response), retry the same batch exactly once with exponential backoff, then fall back to the existing per-page serial finalize loop for the same set of pages. Per-page fallback runs the same per-page `translate(...)` calls that today's pipeline uses.
- Cache hits act as batch boundaries. Only consecutive pages whose preparation produced `.fresh` (not `.cacheHit`) may share a batch. Cached pages still contribute their cached translated bubbles to the rolling recent-context window for later batches, matching today's behavior.
- Mid-batch cancellation is atomic. When `runBatchPipeline` is cancelled while a batch's LLM call is in flight, the in-flight request is cancelled, every page in that batch returns to `.pending`, and no later batches start. Pages that already completed (cache-hit pages, prior batches' translated pages) keep their final state.
- DeepL and Google engines, the per-page `translate(...)` protocol method, `translatePage(at:bypassCache:)` (single-page entry used by retranslate-one), and the OCR/PaddleOCR pipeline are unchanged.

This is **not** a breaking change at the protocol level: the new batch method has a default implementation that delegates to the existing per-page method, so callers and engine implementations that do not opt in keep working.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `contextual-translation`: Relax the per-page rule "page N receives summaries for pages 1..N-1" into a per-batch rule. Within a batch, page-to-page context is carried implicitly by the LLM's own prior output in the same response, so the prompt only injects the rolling recent-context summary for the batch's first page. Cache-hit contribution, failed-page exclusion, page-index ordering across batches, and the 3-page rolling window cap are unchanged. New scenarios cover the batch boundary, cache-hit boundary, fallback after batch failure, and cancel mid-batch.

## Impact

- `MangaTranslator/ViewModels/TranslationViewModel.swift`: new batch scheduler in `runBatchPipeline`'s context-consuming branch; new helper for grouping consecutive miss pages by bubble count; cancel propagation into in-flight batch task.
- `MangaTranslator/Models/Models.swift` or an adjacent service-model file: add `translateBatch(pageInputs:from:to:priorContext:)` with a default extension method that loops to the existing per-page `translate(...)`.
- `MangaTranslator/Services/CopilotTranslationService.swift`: implement `translateBatch` using the structured JSON page schema with the Copilot integration headers already in use.
- `MangaTranslator/Services/OpenAITranslationService.swift`: implement `translateBatch` using the same schema.
- `MangaTranslator/Services/LLMPrompt.swift`: add multi-page user-prompt builder and a single-shot recent-context block that the batch caller passes in.
- `MangaTranslator/Services/LLMResponseParser.swift`: add multi-page response parser with strict page-id validation.
- `MangaTranslatorTests/TranslationViewModelTests.swift`: add batch-pipeline scenarios (grouping, cache-hit boundary, batch failure → per-page fallback, cancel mid-batch).
- `MangaTranslatorTests/CopilotTranslationServiceTests.swift`, `MangaTranslatorTests/OpenAITranslationServiceTests.swift`: add batch request/response tests including parse-failure and partial-response fallback triggers.
- `openspec/specs/contextual-translation/spec.md`: updated by the spec delta in this change.
- DeepL, Google, PaddleOCR, MangaOCR, cache, glossary, model lifecycle: no behavior change.
- Public protocol: `TranslationService` gains one method with a default implementation. No removals.
