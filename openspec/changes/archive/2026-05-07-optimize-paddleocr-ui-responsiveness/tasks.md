## 1. Test Baseline and Non-Blocking Guarantees

- [x] 1.1 Add/extend tests that prove main-actor responsiveness is preserved while high-accuracy OCR runs (single-page path).
- [x] 1.2 Add/extend tests that cover batch and retranslate flows to verify deterministic page state transitions (`processing` → `translated`/`error`) under async OCR execution.
- [x] 1.3 Add regression parity tests that compare optimized high-accuracy OCR output text against approved baseline fixtures with exact-match assertions.
- [x] 1.4 Add boundary/error tests for async OCR path (empty/invalid regions, runtime failure, cancellation-like interruption) and verify strict no-fallback behavior is unchanged.

## 2. Refactor OCR Execution Boundary

- [x] 2.1 Introduce a non-main execution boundary for OCR-heavy compute (service/worker/actor) and keep `TranslationViewModel` UI state mutations on `MainActor`.
- [x] 2.2 Update `OCRRouter` and `MangaOCRService` call chain to use the new async/non-blocking OCR boundary while preserving routing criteria and error contracts.
- [x] 2.3 Ensure high-accuracy runtime access remains serialized/thread-safe after moving compute off main actor.
- [x] 2.4 Keep recognition algorithm inputs/outputs unchanged to preserve baseline output parity.

## 3. Integrate, Harden, and Validate

- [x] 3.1 Update mocks/stubs and existing OCR routing tests to match new async execution boundaries.
- [x] 3.2 Execute existing OCR-related suites (routing, high-accuracy, E2E) and resolve regressions without altering intended OCR behavior.
- [x] 3.3 Verify non-blocking behavior and exact output parity in the full translation flow before marking the change ready for implementation.
