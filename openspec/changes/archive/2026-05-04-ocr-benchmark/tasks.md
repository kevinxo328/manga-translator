## 1. Xcode Project Setup

- [x] 1.1 Add new Unit Test Bundle target `OCRBenchmarkTests` to the Xcode project
- [x] 1.2 Set Host Application to `MangaTranslator` for the new target
- [x] 1.3 Add existing service files (`ComicTextDetectorService`, `MangaOCRService`, `VisionOCRService`) to the `OCRBenchmarkTests` target membership
- [x] 1.4 Create a new Xcode Scheme `OCRBenchmark` that runs only the `OCRBenchmarkTests` target
- [x] 1.5 Verify the main `MangaTranslator` scheme does NOT include `OCRBenchmarkTests`
- [x] 1.6 Add `examples/output/` to `.gitignore`

## 2. BenchmarkReporter

- [x] 2.1 Write failing test for IoU calculation (box overlap = 1.0, no overlap = 0.0, partial overlap)
- [x] 2.2 Implement `IoUCalculator` with `iou(_ a: CGRect, _ b: CGRect) -> Float` function
- [x] 2.3 Write failing test for overlap detection (threshold 0.5, flags larger box)
- [x] 2.4 Implement `BenchmarkReporter` struct with overlap detection logic
- [x] 2.5 Write failing test for report formatting (header, per-image section, summary)
- [x] 2.6 Implement report string generation in `BenchmarkReporter`
- [x] 2.7 Write failing test for output directory creation when missing
- [x] 2.8 Implement `BenchmarkReporter.write(to:)` that creates `examples/output/` if needed and writes timestamped file

## 3. OCRBenchmarkTests

- [x] 3.1 Write failing test for image discovery — finds images at multiple depths, skips non-images
- [x] 3.2 Implement recursive image scanner using `FileManager` and `#file`-derived project root
- [x] 3.3 Write failing test for empty `examples/` — report contains no-images warning
- [x] 3.4 Implement empty directory guard in benchmark runner
- [x] 3.5 Write integration test that runs full pipeline on a single known test image (place one image in `examples/` for CI)
- [x] 3.6 Implement `OCRBenchmarkTests` main test method: scan → detect → IoU → dual OCR → report

## 4. Verification

- [x] 4.1 Switch to `OCRBenchmark` scheme, run `⌘U`, confirm report appears in output/
- [x] 4.2 Switch back to main scheme, run `⌘U`, confirm benchmark tests do NOT run
- [x] 4.3 Run benchmark twice, confirm two separate timestamped report files exist
- [x] 4.4 Verify overlap warnings appear for a known page with merged bubbles
- [x] 4.5 Verify MangaOCR and VisionOCR results appear side-by-side in the report
