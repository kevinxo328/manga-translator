## Why

The current app-side PaddleOCR implementation diverges materially from `scripts/convert_model/verify.py`, including empty outputs, newline-only outputs, and degraded recognition accuracy on known benchmark crops. Investigation has now confirmed that the primary runtime mismatch is in the Swift text-model rotary path, so the project needs a focused fix that restores text-side parity before tuning secondary factors.

## What Changes

- Replace the current Swift PaddleOCR text-model rotary path with a PaddleOCR-VL-compatible implementation instead of relying on `MLXFast.RoPE(...)` directly.
- Re-verify first-step token behavior on the known benchmark empty cases to ensure the Swift runtime no longer terminates with `EOS` or newline when the reference path emits real text.
- Add regression coverage for crop-level parity and benchmark-empty cases so future runtime changes cannot silently reintroduce the same failure mode.
- Remove or downgrade investigation-only debug hooks once the fix is validated, retaining only the minimal regression-testing surface needed for future maintenance.

## Capabilities

### New Capabilities
- `paddleocr-runtime-parity`: Crop-level parity validation for Swift PaddleOCR runtime against the verified reference path, including targeted empty-case regression coverage.

### Modified Capabilities
- `high-accuracy-ocr`: Change the high-accuracy PaddleOCR text runtime so rotary position handling matches the verified reference implementation and no longer produces the confirmed text-side parity failure.
- `ocr-benchmark`: Extend benchmark-oriented validation so known benchmark-empty regions are covered by regression checks tied to the production PaddleOCR path.

## Impact

- Affected code:
  - `MangaTranslatorMLX/PaddleOCREngine.swift`
  - Swift package checkout for `paddleocr-vl.swift` text-model runtime (`LanguageModel.swift`)
  - `OCRBenchmarkTests/OCRBenchmarkTests.swift`
- Affected systems:
  - PaddleOCR high-accuracy OCR runtime
  - OCR benchmark and crop-level regression validation
- Cleanup scope:
  - Investigation-only debug/export hooks introduced during root-cause analysis
