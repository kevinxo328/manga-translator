## 1. Data Model

- [x] 1.1 Define `PairedRegionResult` struct with `mangaBubble: BubbleCluster?`, `visionBubble: BubbleCluster?`, `iou: Float`
- [x] 1.2 Update `ImageResult` to hold `pairedRegions: [PairedRegionResult]`, `unmatchedManga: [BubbleCluster]`, `unmatchedVision: [BubbleCluster]`
- [x] 1.3 Remove `RegionResult` (no longer used)

## 2. IoU Matching

- [x] 2.1 Write tests for the IoU pairing logic: full match, partial match, no match, empty inputs
- [x] 2.2 Implement `BubbleRegionMatcher.match(manga:vision:threshold:) -> (paired, unmatchedManga, unmatchedVision)` using greedy IoU matching (threshold default 0.5)

## 3. BenchmarkReporter

- [x] 3.1 Write tests for updated report format: paired section, unmatched sections, summary counts
- [x] 3.2 Update `generateReport(from:)` to render paired regions with IoU score, MangaOCR text, Vision text
- [x] 3.3 Add unmatched sections (`[Unmatched MangaOCR]` / `[Unmatched Vision]`) per image, omitted when empty
- [x] 3.4 Update summary counts: total paired, unmatched MangaOCR, unmatched Vision, per-engine failure count
- [x] 3.5 Verify `write(result:to:)` still produces timestamped file in `examples/output/`

## 4. Benchmark Test

- [x] 4.1 Remove inline `MangaOCRRecognizer` init, cropping loop, and `VisionOCRService` crop calls from `testFullBenchmark`
- [x] 4.2 Replace with calls to `MangaOCRService.recognizeAndCluster(in:)` and `VisionOCRService.recognizeText(in:)` + `BubbleDetector`
- [x] 4.3 Wire `BubbleRegionMatcher` to produce `ImageResult` and feed into `BenchmarkReporter`
- [x] 4.4 Confirm `testSingleImagePipeline` and `testEmptyExamplesProducesNoImagesWarning` still pass without changes
