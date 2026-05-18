## 1. Foundations — data types

- [x] 1.1 Write failing Swift Testing case asserting that `BubbleCluster` exposes `isInverted: Bool` with `false` as the default for legacy initializers
- [x] 1.2 Add `isInverted: Bool` to `BubbleCluster` in `MangaTranslator/Models/Models.swift`; mark `Codable` with a default value so persisted page state decodes cleanly
- [x] 1.3 Write failing test that constructs an empty `MangaOCRPageResult` with `nil` `textPixelMask` and asserts it round-trips through the manga-OCR pipeline boundary
- [x] 1.4 Introduce `MangaOCRPageResult { let bubbles: [BubbleCluster]; let textPixelMask: CGImage? }` (target file alongside `Models.swift` or in `MangaOCRService.swift` — pick the spot that lets `MangaPage` consume it without circular import)
- [x] 1.5 Introduce an internal `ComicTextDetectorResult { let regions: [DetectedTextRegion]; let textPixelMask: CGImage? }` returned from the detector layer

## 2. Detector — confidence bump and `seg` plumbing

- [x] 2.1 Write failing test: feed `ComicTextDetectorService` a fixture image with a known bbox at conf `0.50` (synthetic or curated) and assert the bbox is rejected; feed another at conf `0.78` and assert it is kept
- [x] 2.2 Keep `ComicTextDetectorService.confidenceThreshold` as a `private static let` named constant
- [x] 2.3 Write failing test asserting `ComicTextDetectorService.detectTextRegions(in:)` returns the new `ComicTextDetectorResult` with a non-`nil` `textPixelMask` whose `>0`-pixel count is between 0.5 % and 12 % of the page area on `examples/001.jpg`
- [x] 2.4 Read and retain the `seg` output (already requested in the existing `ORTSession.run` call); convert it to a binary mask: threshold at `0.5`, dilate by 3 px, resample to original image resolution, wrap as 8-bit grayscale `CGImage`
- [x] 2.5 Write failing test asserting an empty-detection page yields `textPixelMask == nil`
- [x] 2.6 Guard `ComicTextDetectorResult.textPixelMask` so it is `nil` when zero regions survive thresholding

## 3. `isInverted` classifier

- [x] 3.1 Write failing test that constructs a synthetic 1024×1024 canvas with a white-on-dark patch inside a known bbox and asserts the classifier returns `true`
- [x] 3.2 Write failing test that does the inverse (dark-on-white inside the bbox) and asserts `false`
- [x] 3.3 Write failing test for the "interior is entirely text" edge case — bbox whose seg-mask covers >99 % of the central 64×64 sample; assert returns `false` and emits a `DebugLogger` warning
- [x] 3.4 Implement the classifier as a free function `func classifyInverted(canvas: CGImage, seg: CGImage, region: CGRect) -> Bool` in a new file (e.g. `MangaTranslator/Services/BubblePolarityClassifier.swift`). Use BT.601 luminance over a centered 64×64 patch with `seg` pixels excluded; threshold = 128; minimum 16 non-text pixels
- [x] 3.5 Verify all classifier tests pass; verify the threshold constant `128` is centrally located

## 4. Wire into `MangaOCRService`

- [x] 4.1 Write failing test that runs `MangaOCRService.recognizeAndCluster(in:)` on `examples/002.jpg` (which has known inverted bubbles per U5) and asserts the returned `MangaOCRPageResult.bubbles` contains at least 2 clusters with `isInverted == true`
- [x] 4.2 Update `MangaOCRService.recognizeAndCluster(in:)` to return `MangaOCRPageResult` and to compute `isInverted` per bubble using the classifier from §3
- [x] 4.3 Write failing test confirming the returned `textPixelMask` is the same `CGImage` produced by the detector (identity passthrough, not a recompute)
- [x] 4.4 Pass the detector's mask through to the page result; do not recompute

## 5. Update internal callers (compiler-driven)

- [x] 5.1 Update `OCRRouter.processWithMangaOCR(image:)` (and any sibling methods) to consume `MangaOCRPageResult`
- [x] 5.2 Update the batch processing pipeline (search for callers of `recognizeAndCluster`) to thread the new result
- [x] 5.3 Update `MangaPage` state in `Models.swift` (and any `PageState` consumers) so the persisted state retains `textPixelMask` and `isInverted` correctly
- [x] 5.4 Update `OCRBenchmarkTests.testSingleImagePipeline` and related benchmark tests to use the new return type without behavioural change
- [x] 5.5 Update any debug-view consumers (`ImageViewer` debug overlays, `TranslationCard`, etc.) so the build is green; do NOT add new UI in this change

## 6. Benchmark counters

- [x] 6.1 Write failing test for `BenchmarkReporter`: given a page with detections at confidences `[0.95, 0.91, 0.45, 0.52]`, the reported `lowConfidenceDetections` equals 2
- [x] 6.2 Write failing test for `BenchmarkReporter`: given a `MangaOCRPageResult` with 3 `isInverted == true` bubbles, the reported `invertedBubbles` equals 3
- [x] 6.3 Add the two counters to the per-image record in `BenchmarkReporter.swift`; preserve existing fields and the plain-text report shape
- [x] 6.4 Write integration test asserting both counters appear in a generated report for `examples/002.jpg`

## 7. Integration verification

- [x] 7.1 Run the full `OCRBenchmark` scheme against `examples/`; capture the generated report
- [x] 7.2 Confirm no regression: on `examples/001.jpg`, every bubble that was detected pre-change is still detected (current named confidence threshold preserves the observed true positives)
- [x] 7.3 Confirm the two known U13 false positives (`book1/008.jpg` SFX detection, `book1/010.jpg` collar pattern detection) no longer appear in the report
- [x] 7.4 Confirm `invertedBubbles` is `>= 5` across `examples/002.jpg` + `examples/003.jpg` combined (matches U5's 7 inverted bubbles, allowing for minor differences from Swift vs Python preprocessing)
- [x] 7.5 Capture before/after benchmark output snippets into the PR description for review
