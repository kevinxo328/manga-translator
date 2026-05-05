## 1. Benchmark Contract Tests

- [ ] 1.1 Add failing benchmark tests that assert the OCR benchmark uses only production OCR entry points and does not invoke the full-page PaddleOCR engine path
- [ ] 1.2 Add failing report tests for tri-engine comparison output anchored on PaddleOCR vs MangaOCR and PaddleOCR vs Vision OCR
- [ ] 1.3 Add failing report tests for unmatched-region sections and summary counts for all three engines
- [ ] 1.4 Add failing benchmark tests for per-engine latency reporting and failure reporting

## 2. Verification Before Optimization

- [ ] 2.1 Add verification utilities/tests that classify PaddleOCR memory use into model-load peak, warm residency, and per-page inference peak
- [ ] 2.2 Add verification tests that capture decode-loop failure modes, repeated punctuation loops, and token-limit truncation on representative crop-level samples
- [ ] 2.3 Add verification coverage for PaddleOCR-enabled batch/concurrent flows so memory amplification is measured before concurrency changes are proposed
- [ ] 2.4 Document the verification results inside the change artifacts or test notes so later runtime changes are traceable to evidence

## 3. Benchmark Implementation

- [ ] 3.1 Refactor benchmark data structures and matching logic to represent PaddleOCR-vs-MangaOCR and PaddleOCR-vs-Vision comparisons separately
- [ ] 3.2 Implement the production-path PaddleOCR benchmark flow through `OCRRouter` / `MangaOCRService` / `PaddleOCRVLRecognizer`
- [ ] 3.3 Update `BenchmarkReporter` to emit tri-engine comparison sections, unmatched sections, per-engine latency, and per-engine failure counts
- [ ] 3.4 Remove the standalone full-page `testPaddleOCRBenchmark()` path and any report assumptions tied to it
- [ ] 3.5 Run benchmark-focused unit/integration tests and confirm the `OCRBenchmark` scheme remains independently runnable

## 4. PaddleOCR Runtime Stability

- [ ] 4.1 Add failing runtime tests for deterministic unload/reset behavior on recognizer reset, disable/delete flows, and benchmark cold-run setup
- [ ] 4.2 Implement deterministic unload wiring so app-controlled lifecycle events release PaddleOCR runtime memory and the next inference reloads correctly
- [ ] 4.3 Add failing runtime tests for loop detection, repeated-tail cleanup, and deterministic truncation behavior
- [ ] 4.4 Implement minimal decode-stability guards that stop repetitive generation without truncating valid long crop outputs
- [ ] 4.5 Re-run high-accuracy OCR tests and targeted benchmark tests to confirm memory-lifecycle and decode-stability behavior pass without quality regressions

## 5. Final Validation

- [ ] 5.1 Run the relevant unit, integration, and benchmark tests for the changed OCR paths
- [ ] 5.2 Review benchmark runtime against the prior full-page approach and confirm the suite is now practical under the benchmark scheme constraints
- [ ] 5.3 Update any affected developer-facing notes or comments so the benchmark intent clearly states it compares production OCR behavior only
