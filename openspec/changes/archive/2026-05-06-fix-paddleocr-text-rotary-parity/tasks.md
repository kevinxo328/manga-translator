## 1. Regression Harness

- [x] 1.1 Add crop-level regression tests for the known PaddleOCR empty-case regions and assert that the current runtime still fails before the rotary fix.
- [x] 1.2 Add benchmark-oriented regression coverage that exercises the known empty-case crops through the production PaddleOCR path.
- [x] 1.3 Add or retain the minimal test-only hooks needed to inspect first-step token behavior without depending on permanent production debug exports.

## 2. Text Rotary Fix

- [x] 2.1 Replace the Swift PaddleOCR text-model `MLXFast.RoPE(...)` path with a PaddleOCR-compatible rotary implementation and keep the q/k application flow aligned with the verified reference runtime.
- [x] 2.2 Run the targeted crop-level tests after the rotary change and verify that the known empty-case crops no longer terminate with first-step `EOS` or newline.
- [x] 2.3 Run boundary and error-path tests around high-accuracy OCR inference to confirm the rotary change does not break load, unload, or failure behavior.

## 3. Validation And Cleanup

- [x] 3.1 Re-run the OCR benchmark regression coverage and confirm the known benchmark-empty cases now produce non-empty recognition behavior.
- [x] 3.2 Remove or restrict investigation-only debug/export hooks while preserving the regression coverage required by the new parity tests.
- [x] 3.3 Run the relevant OCR test suites end-to-end and confirm the change is ready for implementation handoff.
