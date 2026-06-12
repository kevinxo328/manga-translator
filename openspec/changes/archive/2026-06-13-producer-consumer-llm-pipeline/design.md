## Context

`TranslationViewModel.runBatchPipeline` runs the context-consuming LLM branch in two strict phases: Phase A prepares every page (bounded concurrency 3; OCR itself is serialized behind the `MangaOCRService` actor), Phase B walks the prepared results in page-index order, grouping consecutive `.ready` pages into multi-page LLM batches. The shape was chosen in `archive/2026-05-20-fix-batch-recent-context-order/design.md`, which documented the producer/consumer alternative, its determinism analysis, and the test assertion that would need relaxing. The trade-off accepted then — first-page latency bounded by total OCR time — is the problem this change removes.

Key invariants that must survive (from `contextual-translation`):

- Rolling-window observations and appends happen in ascending page-index order; prompts for the same inputs are unchanged.
- Batch grouping invariants: ≤ 45 bubbles, ≤ 5 pages, consecutive pages only, cache hits / skips / failures are group boundaries.
- Cancellation atomicity per in-flight batch; previously finalized pages keep state and window contribution.

Constraints: `TranslationViewModel` is `@MainActor`; OCR is GPU-bound and already serial (parallel PaddleOCR was measured to blow up memory without throughput gain, so the latency win must come from overlapping OCR with network LLM calls, not from OCR parallelism). The sliding image window from commit `af57f3b` evicts bitmaps in `preparePage`'s defer; the pipeline must not re-pin them.

## Goals / Non-Goals

**Goals**

- First LLM request leaves as soon as page 1's preparation is ready; OCR for later pages overlaps with in-flight LLM calls.
- Byte-identical prompts and rolling-window behavior relative to the shipped pipeline for the same inputs and grouping.
- Keep memory flat: the prepared-page buffer holds bubbles/hashes only, never decoded bitmaps.
- Cancellation leaves the same end state as today, extended to preparations that have not finalized.

**Non-Goals**

- No cancellation UI (no entry point exists today; tracked separately).
- No change to DeepL/Google per-page parallel branch.
- No change to per-page entry points (`translatePage`), batch sizing constants, retry/fallback semantics, or any service-layer code.
- No OCR parallelism changes (`maxConcurrent` stays 3 for preparation I/O; the OCR actor stays serial).

## Decisions

### D1: Ordered buffer + single MainActor consumer, not an AsyncSequence pipeline operator

The producer stays the existing bounded `withTaskGroup`; each completed preparation lands in a `[Int: PagePreparation]` buffer. A single consumer loop (same actor) tracks `nextIndex`, and whenever the preparation for `nextIndex` is present, drains forward. Everything runs on `@MainActor`, so buffer access needs no extra synchronization; the only suspension points are `group.next()` and the LLM calls.

*Alternative considered*: `AsyncStream` feeding a detached consumer task. Rejected — it adds an actor hop per page and a second cancellation surface for no benefit; the ViewModel is already the serialization domain.

Concretely, the consumer is woven into the producer loop: after each `group.next()` result is buffered, the consumer drains as far as `nextIndex` allows. The LLM call suspends the loop; preparations completing meanwhile are collected when control returns. This "interleaved single loop" keeps the structure closest to the shipped code and makes the determinism argument local: consumption order is the loop's own `nextIndex` ordering, regardless of buffer arrival order.

### D2: Dispatch rule — ramp-up group caps (1, 3, 5), count-based, never timing-based

The k-th dispatched LLM batch group has page cap `min(ramp[k], 5)` with `ramp = [1, 3, 5, 5, ...]`. The consumer waits until, starting at `nextIndex`, either that many consecutive fresh-OCR pages are prepared, or accumulation stops early (appending the next prepared page would exceed 45 bubbles; the next prepared page is a cache hit, skip, or failure; the page list ends) — then dispatches. Cache hits, skips, and failures finalize individually and do not consume a ramp slot; only dispatched LLM batch groups advance the ramp ordinal, including groups cut short by a boundary.

Why ramp instead of pure eager dispatch ("drain whatever is ready the moment the translator is idle"):

- **LLM call count stays bounded.** Multi-page grouping exists to compress per-request overhead and per-request quota (GitHub Copilot meters premium requests per call). Pure eager dispatch degenerates to one call per page whenever OCR is slower than the LLM round-trip (PaddleOCR), a 5x quota burn on a 40-page volume. The ramp costs at most 2 extra calls per run (e.g., 40 pages: 10 vs 8) regardless of timing.
- **Determinism is restored.** Group composition becomes a pure function of page count, bubble counts, and cache layout — wall-clock timing never enters the dispatch decision. Spec scenarios state exact compositions, and existing grouping tests update to new expected values without any timing-control machinery.
- **First-page latency is identical to eager.** The first group's cap of 1 means page 1 ships the moment its own preparation completes.

*Alternatives considered*: pure eager dispatch (rejected: unbounded call-count inflation and timing-dependent grouping — surfaced during implementation and decided with the user on 2026-06-12); waiting for the full cap from group 1 (rejected: first page waits for 5 OCR passes, most of the latency win lost); a debounce timer (rejected: nondeterministic and tunable only by guesswork).

### D3: Cancellation — one revert path after the loop exits

Cancellation can now catch pages in three places: finalized (keep state — unchanged), in the cancelled in-flight batch (revert to `.pending` — unchanged), and not yet consumed (newly possible: prepared-but-unconsumed, or preparation still in flight). On cancellation the producer group is cancelled, the consumer stops dispatching, and a single sweep reverts every non-finalized page to `.pending` — reusing the existing `revertRemainingBatchPagesToPending` semantics, applied after the task group has fully drained so no late preparation result can overwrite the revert.

*Alternative considered*: revert eagerly inside each catch site. Rejected — the shipped cancel() vs in-flight-task overwrite race in `ModelDownloadService` (suggestion.md 一-4) is exactly the failure mode of multi-site state finalization; one decision point after quiescence avoids it.

### D4: `restoreFrom` snapshots drop the bitmap at capture time

`preparePage` captures `previousPage` as the restore snapshot for retranslate/engine-switch modes. The restore path reads only `.state` (`TranslationViewModel.swift` finalize branches), so the snapshot's `image` is dead weight that would pin a decoded bitmap inside the buffer for the whole run. The snapshot is captured with `image = nil`. The sliding image window already makes most snapshots nil-image in practice; this makes it structural.

### D5: Test strategy — ordering invariants untouched, grouping expectations updated deterministically

Two classes of existing tests:

- **Ordering-invariant tests** (ascending consumption, no future-page context, window-of-3, cache-hit contribution, failure skipping) encode what this change preserves and must pass with at most expectation updates that follow mechanically from the new groupings.
- **Grouping-composition tests** (`testRunBatchPipelineGroupsFiveLowBubblePagesIntoOneBatch`, flush-threshold and page-cap tests, `testLLMBatchTranslationBuildsRecentContextInPageOrder`'s batch-boundary context expectations) anchored the shipped pipeline's compositions. Under the ramp they get new expected values — e.g., 5 low-bubble pages now produce `[1], [2,3,4], [5]` instead of one batch — computable by hand from the ramp rule with no timing control, because dispatch is count-based (D2).

`testOcrWorkCanStillCompleteBeforeSerialLLMTranslation` asserts `ocrCountAtFirstTranslate == widths.count`; per the archived design note this relaxes (first translation now legitimately starts after page 1's OCR alone). New red tests pin the ramp compositions and the "first batch does not wait for later preparations" property (via an OCR recognizer with controlled per-page latency).

## Risks / Trade-offs

- [Ramp adds up to 2 LLM calls per run → slightly higher per-run quota/token overhead] → Accepted and bounded by construction; chosen explicitly over pure eager dispatch's unbounded inflation (user decision, 2026-06-12).
- [Early pages wait for ramp counts (pages 2-4 wait for 3 preparations) → small readability delay versus pure eager] → Accepted: the user is reading page 1 during that window; OCR stays ahead of reading pace.
- [Subtle reordering bug would corrupt rolling context silently] → The consumer's `nextIndex` ordering is asserted by existing tests that stay unmodified; any regression turns them red.
- [Cancellation sweep misses a late-arriving preparation result] → Sweep runs only after `withTaskGroup` returns (all children joined), so no producer can write after the revert.
- [Interleaved loop complexity in one function] → Extract the drain/dispatch step as a private helper with its own unit-testable seam; keep `runBatch` and `finalizePage` signatures unchanged.

## Migration Plan

Single-PR change to `runBatchPipeline` internals; no persisted state, no API surface, no UI. Rollback = revert the commit. The retranslate entry point (`retranslateAllPages`) flows through the same function and is covered by the same tests.

## Open Questions

(none)
