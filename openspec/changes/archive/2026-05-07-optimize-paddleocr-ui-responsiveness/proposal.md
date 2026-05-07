## Why

When PaddleOCR is enabled, OCR inference currently runs on the main execution path and can block SwiftUI responsiveness, causing macOS beachball during translation. We need to remove UI stalls now because high-accuracy OCR is already shipped and users experience freezes on real workloads.

## What Changes

- Introduce a non-blocking OCR execution model that moves heavy OCR inference work off the main actor while keeping UI state updates on the main actor.
- Preserve existing OCR routing behavior (PaddleOCR vs MangaOCR) and strict error semantics.
- Define a regression contract that high-accuracy OCR text output on the baseline dataset must remain identical after optimization.
- Add concurrency-focused tests for translation/OCR flow to prevent main-thread blocking regressions.

## Capabilities

### New Capabilities
- `non-blocking-ocr-execution`: Ensure OCR-heavy work executes off the UI-critical execution context and keeps the app responsive during translation.

### Modified Capabilities
- `high-accuracy-ocr`: Add a requirement that responsiveness optimizations MUST NOT change baseline recognition text output.

## Impact

- Affected code: `TranslationViewModel`, `OCRRouter`, `MangaOCRService`, `OCRRecognizing`, `PaddleOCRVLRecognizer`, and related OCR tests.
- Affected quality gates: OCR routing tests, high-accuracy OCR tests, and E2E/regression suites for output parity.
- No external API or data format changes expected.
