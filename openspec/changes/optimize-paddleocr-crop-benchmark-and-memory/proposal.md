## Why

The current OCR benchmark mixes production-representative comparisons with a PaddleOCR full-page stress path that does not match the app's crop-level production flow. This makes quality conclusions noisy, keeps benchmark runtime above practical Xcode limits, and obscures the real causes of PaddleOCR memory and decode instability.

## What Changes

- Remove the full-page PaddleOCR benchmark path from the benchmark suite and keep benchmark comparisons aligned with each engine's production pipeline output.
- Extend the OCR benchmark contract so PaddleOCR, MangaOCR, and Vision OCR are compared through their production results, with reporting focused on quality, pairing, unmatched regions, and latency at the page/bubble level.
- Tighten the high-accuracy OCR contract around memory lifecycle and decode stability, including deterministic unload behavior and explicit verification-first tasks for memory peaks and token-loop failure modes.
- Require test-first implementation for benchmark restructuring and PaddleOCR runtime changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ocr-benchmark`: Change benchmark requirements so OCR comparisons are limited to production-representative pipelines and no longer include the PaddleOCR full-page engine benchmark.
- `high-accuracy-ocr`: Clarify runtime requirements for deterministic memory release, verification of memory hot spots before optimization, and decode-stability coverage for token-loop/truncation behavior.

## Impact

- Affected specs: `openspec/specs/ocr-benchmark/spec.md`, `openspec/specs/high-accuracy-ocr/spec.md`
- Affected code: `OCRBenchmarkTests/`, `MangaTranslatorMLX/PaddleOCREngine.swift`, `MangaTranslatorMLX/PaddleOCRVLRecognizer.swift`, related tests under `MangaTranslatorTests/`
- Affected systems: benchmark scheme/runtime, PaddleOCR model lifecycle, OCR quality diagnostics, test strategy
