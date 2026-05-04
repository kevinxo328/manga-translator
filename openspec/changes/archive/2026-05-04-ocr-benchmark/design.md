## Context

manga-translator is a macOS SwiftUI app with a multi-stage OCR pipeline:
1. `ComicTextDetectorService` — YOLOv5 ONNX model detects text bounding boxes
2. `MangaOCRService` — Encoder-Decoder ONNX model recognizes Japanese text
3. `VisionOCRService` — Apple Vision API as fallback
4. `BubbleDetector` — clusters text observations into speech bubbles
5. `ReadingOrderSorter` — sorts bubbles in right-to-left, top-to-bottom order

Two issues have been identified: overlapping bounding boxes from the detector, and inaccurate text recognition on some images (possibly compression-related). A repeatable benchmarking tool is needed to compare engines and isolate root causes.

## Goals / Non-Goals

**Goals:**
- Recursively scan all images under `examples/` regardless of directory depth
- Run `ComicTextDetectorService` on each image and detect overlapping boxes via IoU
- Run both `MangaOCRService` and `VisionOCRService` on each detected region
- Output a timestamped plain-text report to `examples/output/`
- Run independently from the main test suite (separate Xcode Target + Scheme)

**Non-Goals:**
- Ground truth scoring (CER/WER) — future extension
- Visual annotation of bounding boxes on images
- Modifying any existing service code

## Decisions

### Separate Xcode Target instead of adding to MangaTranslatorTests
Using a dedicated `OCRBenchmarkTests` target with its own `OCRBenchmark` scheme keeps the benchmark out of the normal `⌘U` development cycle. Developers only run it when tuning OCR.  
Alternative considered: Adding to existing target with a skip flag — rejected because it adds noise to every test run.

### Host Application: MangaTranslator
The ONNX models are bundled in the app target. Using `MangaTranslator` as the host application for the test bundle gives access to `Bundle.main` resources without duplicating model files.  
Alternative: Copy models into the test bundle — rejected due to binary size and sync overhead.

### Plain-text report over HTML/image annotation
Plain text is the simplest output format that covers the use case: side-by-side OCR text comparison and overlap warnings. HTML requires a template engine; image annotation requires CoreGraphics drawing code. Both add complexity with no immediate benefit.  
Future extension: HTML or annotated images can be added later if needed.

### IoU threshold: 0.5
A box pair with IoU > 0.5 is flagged as a likely duplicate. The warning is attached to the larger box (by area). This threshold is a common default in object detection NMS and can be adjusted.

### Timestamped output files
Each run writes `examples/output/report-YYYYMMDD-HHmmss.txt` rather than overwriting a fixed filename. This preserves history across runs for comparison without requiring git commits.

### Project root via `#file`
The `examples/` directory lives at the repository root, outside any bundle. The test file uses `#file` to derive the project root at compile time, making the path portable across developer machines.

```swift
let projectRoot = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()  // OCRBenchmarkTests/
    .deletingLastPathComponent()  // project root
```

## Risks / Trade-offs

- **Bundle.main dependency** → The benchmark must run with a host app. Running headless (e.g., in CI without the app) requires extra setup. Mitigation: document this constraint; CI is not a goal for this tool.
- **Sequential processing** → Images are processed one at a time. For large `examples/` directories this may be slow. Mitigation: acceptable for an on-demand tool; parallelism can be added later.
- **No ground truth** → The report shows raw OCR output; correctness requires human review. Mitigation: this is by design for the initial version; ground truth scoring is a planned future extension.
