## Context

The benchmark currently runs `ComicTextDetectorService` manually, then crops each detected region and passes the crop to `VisionOCRService` — which is neither the production flow nor an accurate test of Vision recognition quality. `MangaOCRService` is also bypassed in favour of a manually initialised `MangaOCRRecognizer`. The test therefore measures a bespoke pipeline that does not exist in production.

Production pipelines:
- **MangaOCR path**: `MangaOCRService.recognizeAndCluster(in:)` → internally runs `ComicTextDetectorService` then `MangaOCRRecognizer` per region
- **Vision path**: `VisionOCRService.recognizeText(in:)` on the full image → caller clusters results via `BubbleDetector`

## Goals / Non-Goals

**Goals:**
- `testFullBenchmark` calls only production service APIs; no detection or cropping logic inside the test
- Report preserves all existing sections: timestamp, per-image regions, overlap warnings, summary counts, file output
- The two engines are compared via IoU-based pairing of their independently produced bubbles

**Non-Goals:**
- Changing any production service (`MangaOCRService`, `VisionOCRService`, `BubbleDetector`, `OCRRouter`)
- Adding ground-truth labels or automated accuracy scoring
- Changing the `OCRBenchmark` Xcode scheme or test plan

## Decisions

### D1: Each engine runs its own full pipeline independently

Both engines are invoked on the same source image without sharing a detection step. Results are paired afterwards by IoU, not by a shared box.

**Alternatives considered:**
- Shared detection (ComicTextDetector once, both OCR on the same crops): faster, but forces Vision into a crop-based mode it was not designed for and hides real-world detection quality differences.

### D2: IoU pairing with a configurable threshold (default 0.5)

After both engines produce their bubble lists, regions are paired greedily by highest IoU. Unpaired regions from either side are reported as unmatched.

```
MangaOCR bubbles  ──┐
                    ├── IoU matching ──→ PairedRegionResult[]
Vision bubbles    ──┘                    + unmatched lists
```

**Alternatives considered:**
- Centroid distance matching: simpler but breaks when bubble sizes differ significantly.

### D3: New `PairedRegionResult` replaces `RegionResult`

```swift
struct PairedRegionResult {
    let mangaBubble: BubbleCluster?   // nil if unmatched
    let visionBubble: BubbleCluster?  // nil if unmatched
    let iou: Float                    // 0 if unmatched
}
```

`ImageResult` gains separate unmatched lists instead of a flat `regions` array.

### D4: `BenchmarkReporter` is updated in-place, no new type

The existing `generateReport` and `write` methods are updated to accept the new data model. The plain-text format adds a `[unmatched MangaOCR]` / `[unmatched Vision]` section per image. Summary counts remain (failures redefined as unmatched regions).

## Risks / Trade-offs

- **MangaOCRService requires the app bundle**: tests run under `OCRBenchmark` scheme which hosts the app, so the model files are available — no change needed.
- **Vision produces more fine-grained observations than MangaOCR bubbles**: IoU pairing may leave many Vision observations unmatched if BubbleDetector does not merge them. This is acceptable; it surfaces a real quality difference rather than hiding it.
- **Report format change**: existing saved reports will look different from new ones. This is intentional — old reports measured the wrong pipeline.

## Open Questions

- None blocking implementation.
