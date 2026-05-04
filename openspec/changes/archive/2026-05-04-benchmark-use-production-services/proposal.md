## Why

The OCR benchmark currently reimplements its own detection-and-recognition loop inside the test, bypassing `MangaOCRService` and running `VisionOCRService` on small crops — a pattern that differs from production and produces misleading quality metrics. The benchmark should exercise the actual production pipeline so that results reflect real user-facing behaviour.

## What Changes

- Remove inline detection and crop-based OCR logic from `testFullBenchmark`
- Each engine runs its own complete production pipeline independently:
  - MangaOCR path: `MangaOCRService.recognizeAndCluster(in:)` (detect → crop → OCR internally)
  - Vision path: `VisionOCRService.recognizeText(in:)` on the full page → `BubbleDetector` clustering
- Report format changes from per-shared-region comparison to per-engine results with IoU-based region pairing
- `RegionResult` data model updated to reflect independent engine outputs
- `BenchmarkReporter` updated to render the new per-engine layout while preserving all existing report sections (timestamp, image count, overlap warnings, summary counts, file output)

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `ocr-benchmark`: The dual-engine OCR comparison requirement changes from a shared-detection-box model (one box, two OCR results) to an independent-pipeline model (each engine produces its own set of bubbles; report pairs them by IoU where possible)

## Impact

- `OCRBenchmarkTests/OCRBenchmarkTests.swift` — `testFullBenchmark` simplified to call production services
- `OCRBenchmarkTests/BenchmarkReporter.swift` — report rendering updated for new data model
- `MangaTranslator/Services/MangaOCRService.swift` — called directly (no change needed)
- `MangaTranslator/Services/VisionOCRService.swift` — called directly on full image (no change needed)
- `MangaTranslator/Services/BubbleDetector.swift` — called to cluster Vision results (no change needed)
- No changes to production routing, translation, or UI code
