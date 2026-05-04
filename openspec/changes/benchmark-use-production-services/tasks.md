## 1. Data Model

- [ ] 1.1 Define `PairedRegionResult` struct with `mangaBubble: BubbleCluster?`, `visionBubble: BubbleCluster?`, `iou: Float`
- [ ] 1.2 Update `ImageResult` to hold `pairedRegions: [PairedRegionResult]`, `unmatchedManga: [BubbleCluster]`, `unmatchedVision: [BubbleCluster]`
- [ ] 1.3 Remove `RegionResult` (no longer used)

## 2. IoU Matching

- [ ] 2.1 Write tests for the IoU pairing logic: full match, partial match, no match, empty inputs
- [ ] 2.2 Implement `BubbleRegionMatcher.match(manga:vision:threshold:) -> (paired, unmatchedManga, unmatchedVision)` using greedy IoU matching (threshold default 0.5)

## 3. BenchmarkReporter

- [ ] 3.1 Write tests for updated report format: paired section, unmatched sections, summary counts
- [ ] 3.2 Update `generateReport(from:)` to render paired regions with IoU score, MangaOCR text, Vision text
- [ ] 3.3 Add unmatched sections (`[Unmatched MangaOCR]` / `[Unmatched Vision]`) per image, omitted when empty
- [ ] 3.4 Update summary counts: total paired, unmatched MangaOCR, unmatched Vision, per-engine failure count
- [ ] 3.5 Verify `write(result:to:)` still produces timestamped file in `examples/output/`

## 4. Benchmark Test

- [ ] 4.1 Remove inline `MangaOCRRecognizer` init, cropping loop, and `VisionOCRService` crop calls from `testFullBenchmark`
- [ ] 4.2 Replace with calls to `MangaOCRService.recognizeAndCluster(in:)` and `VisionOCRService.recognizeText(in:)` + `BubbleDetector`
- [ ] 4.3 Wire `BubbleRegionMatcher` to produce `ImageResult` and feed into `BenchmarkReporter`
- [ ] 4.4 Confirm `testSingleImagePipeline` and `testEmptyExamplesProducesNoImagesWarning` still pass without changes
