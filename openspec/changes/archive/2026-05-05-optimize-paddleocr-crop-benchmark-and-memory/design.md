## Context

The repository currently has two different evaluation shapes for OCR quality:

- `testFullBenchmark()` compares production-style MangaOCR and Vision OCR outputs through their service APIs and IoU pairing.
- `testPaddleOCRBenchmark()` bypasses the app pipeline and sends full-page images directly to `DefaultPaddleOCREngine`.

That split makes the benchmark hard to interpret. The app's Japanese OCR production path is crop-level via `OCRRouter -> MangaOCRService -> OCRRecognizing`, while the standalone PaddleOCR benchmark measures a full-page engine stress path. Existing investigation also shows that the full-page path is slower, more memory-hungry, and more prone to token loops than crop-level usage.

This change needs to keep benchmark conclusions aligned with production behavior, preserve meaningful cross-engine comparison, and improve PaddleOCR runtime stability without making speculative optimizations first. The user also requires test-driven development, so verification tasks must come before runtime changes.

## Goals / Non-Goals

**Goals:**

- Keep OCR benchmark comparisons aligned with production OCR flows for PaddleOCR, MangaOCR, and Vision OCR.
- Remove the full-page PaddleOCR benchmark path from the benchmark suite and reports.
- Add benchmark reporting that can compare PaddleOCR against MangaOCR and Vision OCR without introducing non-production preprocessing into the tests.
- Define a verification-first workflow for PaddleOCR memory and decode instability before implementation changes are made.
- Require tests to be added or updated before production code changes.

**Non-Goals:**

- Replacing the current production OCR routing architecture.
- Converting Vision OCR to a detector-crop pipeline for benchmarking symmetry.
- Reintroducing a standalone full-page PaddleOCR quality benchmark.
- Changing model conversion tooling or quantization policy in this change unless verification proves it is necessary.

## Decisions

### D1: Benchmark only production pipeline outputs

The benchmark will compare each OCR engine through the same production entry shape it uses in the app:

- PaddleOCR path: `OCRRouter` / `MangaOCRService` with `PaddleOCRVLRecognizer`
- MangaOCR path: `MangaOCRService`
- Vision OCR path: `VisionOCRService` + `BubbleDetector`

The benchmark test will no longer call `DefaultPaddleOCREngine.infer(image:)` on a full-page image.

Alternative considered:

- Keep both production and full-page benchmarks. Rejected because the full-page result is not a production quality signal and dominates runtime while adding little decision value.

### D2: Use PaddleOCR as the comparison anchor for tri-engine reporting

The report model will pivot around PaddleOCR, because this change is specifically evaluating whether PaddleOCR is a production-quality upgrade over the existing pipelines. For each image:

- Pair PaddleOCR vs MangaOCR by greedy IoU matching
- Pair PaddleOCR vs Vision OCR by greedy IoU matching
- Record unmatched regions for each comparison independently

This avoids an unreadable all-pairs comparison matrix while still answering the product question: how PaddleOCR behaves relative to the two existing production OCR paths.

Alternative considered:

- Compute every pair (`Paddle↔Manga`, `Paddle↔Vision`, `Manga↔Vision`). Rejected because it increases report complexity and implementation scope without improving the key decision signal for this change.

### D3: Treat memory optimization as a verified runtime problem, not a benchmark assumption

The implementation work will start by measuring and classifying memory use into distinct buckets:

- model load peak
- warm-runtime residency
- per-page inference peak
- batch concurrency amplification

Only after those measurements exist will runtime changes be applied. This keeps the change evidence-based and prevents speculative optimizations that might trade away stability or quality.

Alternative considered:

- Immediately lower memory by adding more aggressive unloads, lower token limits, or different image routing. Rejected because current evidence does not yet separate load-time, decode-time, and concurrency-related memory pressure.

### D4: Make deterministic unload the primary release mechanism

The runtime contract will rely on explicit unload/reset hooks as the deterministic release path. Memory-pressure-triggered release remains part of the contract, but it is treated as supplemental rather than the only guarantee. App-controlled events such as recognizer reset, mode switch, model deletion, and benchmark cold-run setup should all be able to force model release.

Alternative considered:

- Rely only on `NSApplication.didReceiveMemoryWarningNotification`. Rejected because that signal is not sufficiently deterministic for macOS lifecycle control and does not satisfy the observed runtime behavior.

### D5: Add decode-stability guards as behavioral correctness, not cosmetic post-processing

Repeated-token loops and token-budget exhaustion will be handled as runtime correctness issues. The design will allow:

- loop detection during generation
- bounded decode budgets appropriate to crop-level OCR
- explicit handling of truncation/loop cases in tests

This is preferred over treating repeated output as a report-only cleanup problem, because the current failure mode wastes runtime and contributes to perceived memory pressure.

Alternative considered:

- Only trim repeated phrases after generation finishes. Rejected because it does not recover latency or memory wasted on a loop that already consumed the decode budget.

### D6: Test-driven sequencing is part of the implementation design

The change will be implemented in this order:

1. add/adjust benchmark and runtime tests to capture desired behavior
2. add verification tests/instrumentation for memory and decode failure modes
3. change production code to satisfy those tests

This sequencing is necessary because the benchmark contract itself is changing, and the runtime optimizations need guardrails against silent regressions.

## Risks / Trade-offs

- [Tri-engine reporting adds a new report shape] → Keep the data model focused on PaddleOCR-vs-existing comparisons instead of building a full pairwise matrix.
- [Verification-first work increases up-front effort] → Accept this cost to avoid speculative memory changes and to preserve OCR quality.
- [More aggressive unload behavior may increase cold-start latency] → Separate cold and warm benchmark scenarios so memory improvements do not hide reload costs.
- [Decode-loop guards may accidentally truncate legitimate long text] → Add explicit tests for long-but-valid crop outputs and validate limits against benchmark samples before finalizing thresholds.

## Migration Plan

1. Update benchmark specs and tests to remove the full-page PaddleOCR path and define tri-engine production comparisons.
2. Add failing tests for deterministic unload, decode-loop handling, and benchmark report structure.
3. Add verification utilities/tests that classify memory behavior for load, warm residency, and per-page inference.
4. Implement runtime lifecycle and decode stability changes only after the verification stage is in place.
5. Remove obsolete full-page benchmark code and assertions once the production benchmark path is green.

## Open Questions

- What decode-token ceilings best fit crop-level OCR without truncating legitimate dense bubbles?
- Whether batch translation concurrency should be reduced for PaddleOCR-enabled flows depends on measured evidence from the verification stage.
