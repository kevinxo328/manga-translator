## Context

`fix-batch-recent-context-order` (archived 2026-05-20) replaced the single-phase concurrent batch pipeline with a two-phase pipeline for context-consuming LLM engines: a bounded-concurrency preparation phase (OCR + cache lookup, 3 pages in flight) followed by a strictly serial, page-index-ordered finalize phase. The serial finalize phase is the conservative "prep-all-then-finalize" shape documented in that change's `design.md`. The shape provides deterministic recent-context but the LLM API calls now run one at a time, after every page's preparation is complete. For an N-page batch the LLM phase regressed from `(API/3) * N` to `API * N`, and page 1's API call now waits for every page's OCR, not just its own.

`fix-batch-recent-context-order/design.md:101` explicitly listed a "Producer/Consumer LLM Pipeline" as the deferred throughput optimization and noted the assertion `testOcrWorkCanStillCompleteBeforeSerialLLMTranslation` would need relaxing. We choose a different throughput strategy here — multi-page batching in a single LLM request — because it lets us recover throughput in one round-trip per batch (3-5 pages per call) without introducing an ordered async buffer or relaxing the OCR/translation interleaving assertion in a way that requires new pipeline plumbing.

Active capabilities affected: `contextual-translation` (rolling 3-page window). All other capabilities (cache-management, translation-cache, ocr-routing, paddleocr-recognizer, glossary-management, local-model-lifecycle) are untouched.

Concurrency baseline: `TranslationViewModel` is `@MainActor`. Phase A uses `withTaskGroup` with `maxConcurrent = 3`. Translation services are `Sendable` and called from background tasks. `URLSession`-based services already support cancellation via `Task.cancel()`.

## Goals / Non-Goals

**Goals:**

- For batch translation runs (`translateBatch()` and `retranslateAllPages()`) on `githubCopilot` and `openAICompatible` engines, group up to 5 consecutive miss pages with at most 45 total bubbles into one `translateBatch` LLM call.
- Preserve every existing `contextual-translation` invariant that is not explicitly relaxed by the spec delta: page-index ordering across batches, the 3-page rolling window cap, cache-hit contribution, failed-page exclusion, glossary context for DeepL/Google.
- Make the new path a strict throughput win in the happy path (single API call per N pages) and preserve today's correctness in the failure path (retry once, then run today's per-page serial loop). Failure latency may be worse than today because the system spends one failed batch attempt and one retry before falling back.
- Keep the per-page `TranslationService.translate(...)` contract unchanged. The new `translateBatch` method ships with a default implementation that delegates to the per-page method so non-LLM engines and tests that only implement the per-page contract keep working.
- Keep mid-batch cancel deterministic: pages in the in-flight batch return to `.pending`, no later batches start, no partial results from the batch are persisted to UI or cache.

**Non-Goals:**

- Producer/consumer pipeline with an ordered async buffer (the previously deferred alternative). Multi-page batching achieves the throughput goal with simpler concurrency.
- Changes to DeepL or Google translation paths. They already run with 3-way concurrent per-page calls and are not in the user-reported regression scope.
- Streaming LLM responses. Within a batch, response parsing happens after the full response body arrives. Adding SSE-style streaming is a separate change.
- Changes to OCR, bubble detection, reading-order sort, cache schema, glossary, or model lifecycle.
- Per-page retranslate (`translatePage(at:bypassCache:)`). Single-page entry keeps using the per-page `translate(...)` method directly.
- Token-budget-based batch sizing using a real tokenizer. Bubble count is the proxy for this version. If bubble count proves insufficient in practice, a follow-up change can layer token estimation on top.

## Decisions

### Decision 1: Multi-page batching over producer/consumer pipeline

We add a `translateBatch(pageInputs:from:to:priorContext:)` method to `TranslationService` that takes an ordered array of page inputs and returns an ordered array of page outputs in one API call. The batch scheduler in `TranslationViewModel` groups consecutive miss pages from the prepared batch and calls this method instead of looping per-page `translate(...)`.

The batch method uses a dedicated prompt contract, separate from the existing per-page prompt contract:

Request user prompt:

```json
{
  "pages": [
    {
      "page_id": "1",
      "bubbles": [
        {"index": 0, "x": 120, "y": 40, "width": 80, "height": 50, "text": "..."}
      ]
    }
  ]
}
```

Response body:

```json
{
  "pages": [
    {
      "page_id": "1",
      "bubbles": [
        {"index": 0, "translation": "translated text here"}
      ],
      "detected_terms": [
        {"source": "original proper noun", "target": "translated proper noun"}
      ]
    }
  ]
}
```

The batch system prompt must instruct the LLM to return only this object shape. The existing per-page `LLMPrompt.systemPrompt(...)` response instruction remains unchanged for `translate(...)`.

Why this over producer/consumer:

- One LLM round-trip per 3-5 pages versus N round-trips for N pages. For typical manga batches dominated by API latency, this is the same throughput recovery as v1.4.6 without per-page concurrency.
- No ordered async buffer. The batch scheduler is a simple `for` loop over groups inside the existing `runBatchPipeline`.
- The existing OCR-vs-LLM interleaving assertion (`testOcrWorkCanStillCompleteBeforeSerialLLMTranslation`) keeps holding because Phase A still runs prep-all-then-finalize: OCR for all pages still completes before any LLM call starts. We retain the explicit two-phase shape; only Phase B's loop body changes from per-page to per-batch.

Alternatives considered:

- Producer/consumer pipeline (deferred in `fix-batch-recent-context-order/design.md:101`). Rejected for this change because the ordered async buffer adds concurrency surface (cancellation correctness, backpressure if LLM is slower than OCR) without giving a larger throughput win than batching in our typical workloads.
- Connection keep-alive and prompt caching alone. Both reduce per-call latency but still issue N calls. Useful complements but not a substitute for fewer round-trips.

### Decision 2: Within-batch context is implicit; recent-context summary injected at batch boundary only

For a batch containing pages `[F, F+1, ..., L]`, the LLM prompt includes one `## Recent context` block that summarizes up to the 3 most recent successful pages whose index is strictly less than `F`. Pages `F+1..L` are not given an additional explicit summary for `F..k-1`; instead they appear in the same user prompt and the model's generated output for page `k` is available to its own attention while it generates page `k+1`'s translation in the same response.

Why:

- Modern LLMs strongly attend to their own prior output within one response. Per-batch-boundary explicit summary plus within-batch implicit context is sufficient for the qualitative consistency that `contextual-translation` aims for.
- A single `Recent context` block per batch keeps prompt size predictable and avoids redundant tokens.
- The page-index ordering invariant across batches is unchanged: batch starting at page `F` still sees pages `< F`, never pages `≥ F` from a future batch.

Alternatives considered:

- Repeat per-page `Recent context` headers inside the batch user prompt. Rejected — wastes tokens and contradicts the "one prompt one response" structure.
- Treat the whole batch as a single logical page for the rolling window. Rejected — loses per-page boundaries in the summary fed to the next batch and would observably reduce translation consistency across batch boundaries.

### Decision 3: Bubble-count threshold, hard page cap, single-page overflow

A batch group is formed by greedily appending consecutive miss pages while both invariants hold:

- `sum(bubbles per page) + nextPage.bubbles ≤ 45`
- `pages in group + 1 ≤ 5`

Flush the group when either invariant would break, or when the next prepared page is a cache hit (see Decision 4), or when the page list is exhausted.

A single page with `bubbles > 45` becomes a batch of exactly 1 (no further sub-splitting). The batch method must still accept this case and the per-page fallback path must remain reachable for it.

Why bubble count and not token count:

- Bubble count is locally available without tokenizing prompt text. CJK content has variable bytes-per-token; a heuristic char-to-token ratio is brittle. Bubble count, combined with the engine-side `max_tokens` cap, is a reliable proxy for "this batch fits inside one request".
- The numeric thresholds are tunable constants (`BatchSizingConfig.maxBubbles = 45`, `BatchSizingConfig.maxPages = 5`) so they can be adjusted without changing the algorithm. A follow-up change may swap the heuristic for a tokenizer-based estimate; this decision does not block that.

### Decision 4: Cache hits act as batch boundaries

Within Phase B's iteration over prepared pages, a `.cacheHit` preparation flushes the current batch group (if any) before being applied. The cached page contributes its bubbles to the rolling recent-context window and is marked `.translated`; it never enters an LLM batch.

Why:

- Including cached pages in the batch prompt would either (a) waste tokens by sending source + cached translation as `do-not-translate` context, or (b) skip them in the prompt and create a gap between pages `[F, F+2]` that contradicts Decision 2's implicit-ordering claim.
- The cache-hit-contributes-to-recent-context invariant from `contextual-translation/spec.md` is preserved exactly: cached translated bubbles are appended to the rolling window in page-index order just as today.
- The throughput cost (more batches when cache hits are scattered) is acceptable because scattered-cache batches are an inherently mixed workload; users who experience the slowdown most strongly are running fresh batches where all pages are misses and Decision 3 forms maximally-sized groups.

### Decision 5: Failure mode — retry batch once, then per-page serial fallback

When a batch call fails for any of the following reasons, the batch is retried exactly once after exponential backoff (starting at 500ms with x2 multiplier):

- HTTP non-2xx response from the provider
- Transport-level error (timeout, connection failure)
- Response JSON parse failure
- Valid JSON but missing one or more requested page ids
- Valid JSON but containing one or more unexpected page ids

User-initiated cancellation is not a batch failure. `CancellationError`, `URLError.cancelled`, and any service-level cancellation wrapper must propagate to the scheduler without retry, sanitization, or per-page fallback.

If the retry also fails for any of the same non-cancellation reasons, the scheduler falls back to calling the per-page `translate(...)` method for each page in the failed batch group, in page-index order, exactly as today's Phase B does. Per-page fallback uses the existing per-page retry inside each service (`maxRetries = 2` already in `CopilotTranslationService`).

Why:

- The retry catches transient transport and rate-limit errors without taking the per-page latency hit.
- The per-page fallback guarantees that correctness is no worse than today's pipeline. Token-budget overruns, model "forgot a page" errors, and provider safety filter trips that strike a batch but not a single page all converge through this safety net. Latency is worse than today's pipeline when batch failure is common, so fallback events must be logged and monitored.
- No split/binary retry is introduced. Modern LLM context windows make token-overrun-of-3-page batches with our 45-bubble cap rare in practice; the per-page fallback handles even those without extra code paths.

Alternatives considered:

- Split-and-retry (binary). Rejected — adds code that handles a rare case the per-page fallback already covers.
- Mark the whole batch as `.error` without fallback. Rejected — the user would lose pages that have nothing wrong with them.

### Decision 6: Mid-batch cancel is atomic

The batch scheduler runs each batch as a child task inside `runBatchPipeline`. On cancellation:

- The in-flight `translateBatch` call's underlying `URLSessionDataTask` is cancelled via `Task.cancel()` propagation.
- Every page in the cancelled batch returns to `.pending`. The batch's partial state (if any tokens were received but the request did not complete) is discarded.
- The scheduler does not start the next batch. Pages that already completed (cache-hit pages, prior batches' translated pages, prior batches' fallback-route results) keep their final state.
- `isProcessing` is set to `false` after the scheduler exits.

Why:

- Atomic per-batch units match the user mental model: "cancel" means stop now. Salvaging partial JSON would either require streaming + incremental parse (added complexity) or could surprise the user with "some pages of the batch I cancelled actually got written".
- Partial parse of an incomplete response is fragile: most providers send the full JSON only after the closing brace; trying to parse mid-stream would create a per-engine streaming contract that is out of scope.

### Decision 7: Default `translateBatch` falls back to per-page

The protocol method ships as:

```
extension TranslationService {
    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        // Default: delegate to per-page translate(...) in page-index order.
        // Engines that want true batching override this method.
    }
}
```

Why:

- DeepL and Google do not get a true batch implementation. The default keeps them functional if the scheduler ever routes through `translateBatch` for them (it does not in this change, but the protocol contract should not require every engine to handle batching).
- Test fakes that only implement `translate(...)` keep working without modification.
- This is the minimal protocol surface that preserves backward compatibility.

### Decision 8: Per-page retranslate stays per-page

`translatePage(at:bypassCache:)` continues to call `service.translate(...)` directly. The new batch path is only inside `runBatchPipeline` (used by `translateBatch()` and `retranslateAllPages()`).

Why:

- A single-page entry has no batching to do; constructing a batch of 1 to take the new path would add code with no behavior change.
- Mixing the two entry points keeps per-page retry semantics (which are part of the per-page UX contract) untouched.

## Risks / Trade-offs

- [Risk] LLM within-batch self-attention is weaker than explicit recent-context summary, producing per-page translations of slightly different quality than today's serial pipeline. → Mitigation: spec delta documents the relaxation explicitly. Add a test that compares per-page-vs-batch output structure (each requested page id is present and ordered) but not literal text. If field reports show consistent quality regression, future change can fall back to "batch the prompt structure but explicitly include page N-1's translation in page N's section".

- [Risk] `Recent context` block at batch boundary plus within-batch implicit context drifts the rolling window semantics slightly: `currentContext` after batch `[F..L]` finalizes appends all pages `F..L` in page-index order. If the same window were observed mid-batch it would be empty for `F..L`. → Mitigation: the rolling window's only observable consumer is the next batch's `priorContext`, and observation is always between batches. The spec delta states the window is sampled at batch boundaries.

- [Risk] Multi-page response missing one or more page ids would silently succeed if the parser does not validate. → Mitigation: parser strictly checks every requested page id appears in the response; missing pages count as parse failure and trigger the retry-then-fallback path.

- [Risk] Per-page fallback path latency is worse than today (we tried batch, it failed, then we ran per-page). → Mitigation: log batch-fallback events through `DebugLogger` with a stable category so the failure rate can be monitored. If batches fail often enough to make fallback the common path, this change should be reverted.

- [Risk] Tokens spent on the system prompt and `Recent context` block are no longer amortized across N per-page calls; they are inside one batch prompt. For a 3-page batch the input-token-per-translated-page actually decreases (one system prompt, one recent-context block, three pages' bubbles versus three full system+context+bubbles prompts). → Mitigation: noted as a side benefit. Anthropic prompt caching (if added later) would amplify this further.

- [Risk] Tests that hardcode "every page produces one API call" assumption (e.g., `OpenAITranslationServiceTests`, `CopilotTranslationServiceTests` invocation-count assertions) will break. → Mitigation: tasks file enumerates the affected test names; they need to be re-stated as "every page is translated exactly once via either batch or per-page path" rather than counting raw calls.

- [Risk] Mid-batch cancellation while the request is partially-uploaded may leak a connection or log a benign cancellation error in `DebugLogger`. → Mitigation: log cancellation at `.info` not `.error`. The connection cleanup is `URLSession`'s responsibility; no manual handling needed.

- [Risk] A single page that exceeds 45 bubbles becomes a batch of 1, which is functionally equivalent to today's per-page call. If such pages are common, this change does not help them. → Mitigation: acceptable — they were no slower than today before, and they remain no slower than today. The bubble threshold can be tuned.

## Migration Plan

This is a code-only change. There is no schema migration, no UserDefaults migration, no on-disk data change.

Deployment:

1. Land the change behind the default code path (no feature flag). The new path is engaged automatically when the user runs batch translation on a context-consuming LLM engine.
2. The per-page fallback inside the new path provides a graceful runtime safety net.

Rollback: revert the commit. The per-page fallback is the prior pipeline, so a revert removes the new code without leaving stale state.

## Open Questions

None. All design decisions in the prior explore conversation are settled:

1. Within-batch context is implicit (Decision 2).
2. Bubble-count threshold = 45 bubbles, max 5 pages (Decision 3).
3. Retry once then per-page fallback (Decision 5).
4. Cache hits break batches (Decision 4).
5. Engine scope = Copilot + OpenAI Compatible (Goals).
6. Cancel mid-batch = drop and revert to `.pending` (Decision 6).
7. Per-page retranslate unchanged (Decision 8).
