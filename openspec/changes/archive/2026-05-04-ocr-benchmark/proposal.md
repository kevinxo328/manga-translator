## Why

The OCR pipeline has two known issues: text detection produces overlapping bounding boxes (a large box enclosing smaller ones), and some text recognition results are inaccurate (possibly related to JPEG compression). A repeatable comparison tool is needed so developers can quickly evaluate MangaOCR vs VisionOCR differences when tuning OCR behavior.

## What Changes

- Add a new Xcode Target `OCRBenchmarkTests` and Scheme `OCRBenchmark`, excluded from the main App test action
- Add `OCRBenchmarkTests.swift`: recursively scans `examples/`, drives the comparison test flow
- Add `BenchmarkReporter.swift`: collects results, computes IoU, generates a plain-text report
- Report written to `examples/output/report-YYYYMMDD-HHmmss.txt` (timestamped, history preserved)
- Add `examples/output/` to `.gitignore`

## Capabilities

### New Capabilities

- `ocr-benchmark`: Run MangaOCR and VisionOCR comparison on images under `examples/`, detect overlapping bounding boxes, and output a human-readable plain-text report

### Modified Capabilities

## Impact

- New Xcode Target and Scheme (requires manual configuration in .xcodeproj)
- Reuses existing `ComicTextDetectorService`, `MangaOCRService`, and `VisionOCRService` without modifying any existing code
- `examples/output/` added to `.gitignore`
