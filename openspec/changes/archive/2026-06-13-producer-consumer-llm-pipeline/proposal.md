## Why

For context-consuming LLM engines, the batch pipeline currently prepares (OCR) every page before the first LLM request is sent. On a 40-page volume the first readable page therefore waits for the entire OCR pass — minutes of GPU work — while the network sits idle, and then the LLM phase runs while the GPU sits idle. The producer/consumer alternative was already analyzed and deliberately deferred in `archive/2026-05-20-fix-batch-recent-context-order/design.md` ("Deferred Optimization: Producer/Consumer LLM Pipeline"); this change implements it. It cuts time-to-first-readable-page from "all pages OCR'd + first batch" to "page 1 OCR'd + a one-page batch" with no extra memory and no parallel PaddleOCR inference.

## What Changes

- `TranslationViewModel.runBatchPipeline` (context-consuming LLM branch only): replace the two-phase "prepare all, then finalize" shape with a pipelined producer/consumer. Preparation keeps its bounded concurrency (3); a single ordered consumer starts finalizing as soon as the lowest-index unconsumed page's preparation is ready.
- Batch grouping gains a ramp-up dispatch rule: the k-th LLM batch group waits for at most `ramp[k]` consecutive prepared miss pages, with `ramp = [1, 3, 5, 5, ...]` (existing invariants unchanged: ≤ 45 bubbles, ≤ 5 pages, cache hits and failures are boundaries). The first group ships as soon as page 1 is prepared (minimal first-page latency); group sizes return to the full cap by the third group, so the total LLM call count increases by at most 2 per run versus the shipped pipeline — it cannot degenerate into one call per page. Grouping is a pure function of page count, bubble counts, and cache layout — never of OCR/LLM timing — so behavior and tests stay deterministic.
- Deterministic page-ordered context is preserved: the consumer advances strictly in ascending page index, so all rolling-window ordering rules hold exactly as today (no page ever sees a later page; ascending order; window of 3). Because groups are smaller early in a run, more pages sit at group boundaries and receive explicit recent-context summaries instead of implicit within-batch context; this changes prompt grouping versus the shipped pipeline but stays within the same spec rules.
- Mid-run cancellation extends to preparations: in-flight/unstarted preparations stop, and pages not yet finalized return to `.pending` alongside the existing in-flight-batch revert rules.
- `PagePreparation.restoreFrom` snapshots are stripped of their `NSImage` so the prepared-page buffer never pins decoded bitmaps (the restore path only reads `.state`).
- Relax `testOcrWorkCanStillCompleteBeforeSerialLLMTranslation`'s over-tight assertion (`ocrCountAtFirstTranslate == widths.count`) as pre-announced by the archived design note.
- Non-context engines (DeepL, Google) keep their existing per-page parallel pipeline untouched — they already start translating after their own page's preparation.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `contextual-translation`: "Multi-page LLM batch grouping" gains the pipelined dispatch rule (a group contains only pages already prepared when the translator goes idle; first LLM request no longer waits for all preparations). "Mid-batch cancellation is atomic" extends to cover preparations still in flight. Rolling-window ordering requirements are unchanged.

## Impact

- **Code**: `MangaTranslator/ViewModels/TranslationViewModel.swift` (`runBatchPipeline`, `preparePage` restoreFrom snapshot, batch group drain logic). No service-layer changes; `ChatCompletionsClient`, `LLMPrompt`, and OCR routing are untouched.
- **Tests**: `MangaTranslatorTests/TranslationViewModelTests.swift` — new pipelining/grouping/cancellation tests (TDD), plus relaxing one existing assertion. Existing batch-ordering tests must stay green unmodified (they encode the determinism guarantee).
- **Specs**: delta to `openspec/specs/contextual-translation/spec.md` only; `batch-processing` already mandates progressive background translation and a concurrency cap of 3, both preserved.
- **No UI changes**: cancellation UI entry remains out of scope (tracked separately as suggestion.md item 一-5).
