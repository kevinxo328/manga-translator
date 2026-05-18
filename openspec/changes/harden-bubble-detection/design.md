## Context

The manga-OCR pipeline runs `comic-text-detector.onnx` to localize bubbles, then `manga-ocr.onnx` (or PaddleOCR) to recognize the text inside each region. The detector model already exposes three heads — `blk` (YOLOv5 bounding boxes), `seg` (a polarity-agnostic per-pixel text mask), and `det` (DBNet-style line-level probability/threshold maps) — but `ComicTextDetectorService` only consumes `blk`. The session already requests all three outputs and discards two, so wiring them up costs zero additional ONNX inference time.

Phase 2 of the roadmap (text overlay composited onto the page) needs a per-pixel text mask to know which pixels to inpaint, and a polarity signal so it does not paint white on a black narration box. Phase 1 verification (ROADMAP §3 entries U1b, U2, U5, U6, U10, U13) showed:

- The `seg` head is the text-pixel mask we need; it ignores polarity and segments inverted text equally well.
- Bubble-interior luminance is strongly bimodal (median 253 for normal, ~0 for inverted, near-zero density 50–200); a fixed luminance threshold suffices.
- The model emits ~99 % `class=bubble` and almost no `class=text` on the 17-page corpus; the "text-line ↔ bubble association" port originally planned (1.3) has no signal to operate on.
- 2 / 139 visible false positives, both at `conf < 0.6`, while all true positives sit at `conf ≥ 0.77`; the Phase 1 plan keeps the shared confidence threshold as a named constant rather than hard-coding a new cutoff in the roadmap.

This change wires those two outputs into the public pipeline surface and adjusts one constant. It deliberately does *not* attempt the originally-scoped 1.3 / 1.4 / 1.5 / 1.7 tasks, because verification showed they target failure modes that do not exist on the current corpus.

## Goals / Non-Goals

**Goals:**
- Surface the `seg` head as a per-page binary text-pixel `CGImage` on the OCR pipeline result.
- Add `isInverted: Bool` to each `BubbleCluster`, derived from `seg`-masked interior luminance.
- Keep `ComicTextDetectorService.confidenceThreshold` as a named constant for now.
- Add two counters (`lowConfidenceDetections`, `invertedBubbles`) to the OCR Benchmark report.
- Keep the change small enough that Phase 2 can build on it without further detector work.

**Non-Goals:**
- Per-class confidence thresholds. U6 shows no headroom and class 0 is essentially absent.
- Porting upstream `group_output` for text-line ↔ bubble association. U2 shows there are no text-line detections to associate.
- A title/SFX position heuristic. U13 and U15 do not justify promoting it into the core Phase 1 scope.
- Consuming the `det` (DBNet) head. Phase 2's inpaint route does not need it.
- Per-pixel bubble-shape extraction. Phase 2 will inpaint text pixels directly (`seg` is already what we need); the bubble outline is irrelevant.
- ML inpainting. Phase 3 territory.

## Decisions

### D1. Expose `seg` as a single page-level `CGImage`, not per-region masks

The downstream consumer (Phase 2's inpaint step) operates on the whole page in one pass, the way `cv2.inpaint` and equivalents expect. Slicing the mask per bubble would force Phase 2 to stitch crops back together and would lose the SFX pixels that fall outside any bubble bbox.

Alternative considered: attach a `mask: CGImage?` field to each `DetectedTextRegion`. Rejected — the seg mask is a page-level signal (it covers SFX outside any region), so cropping it into per-region pieces throws away information.

### D2. Encode the mask as binary at original image resolution

The `seg` output is float32 `[1, 1, 1024, 1024]` in normalized 0–1 space (sigmoid is internal to the model — verified in U1b raw stats). The pipeline shape is: threshold at `0.5` → binary uint8 → dilate by 3 px (matches the U10 inpaint spike that produced acceptable results) → resize to original image resolution using nearest-neighbor → wrap as an 8-bit grayscale `CGImage`.

Alternative considered: preserve the float confidence as grayscale. Rejected for v1 — Phase 2's MVP uses Telea inpainting which only consumes a binary mask. Soft edges can be added later if a more sophisticated inpainter (Phase 3) needs them.

Resolution choice: native image resolution (not 1024) so Phase 2 can composite without rescaling. The mask is a small fraction of the original image weight (binary at native size, typically <100 KB).

### D3. `isInverted` is a `Bool` derived from interior luminance

Per-bubble: sample the central 64×64 region in 1024-space, exclude pixels where `seg >= 0.5` (the text glyphs themselves), compute BT.601 luminance, and set `isInverted = mean_luminance < 128`. If fewer than 16 non-text pixels survive (i.e. the entire interior is text), default to `false` and emit a debug log line.

U5 corpus stats justify the binary choice: 132 bubbles cluster at luminance 251–254 (p10 251, p90 254), 7 cluster at ~0, and the 50–200 zone is essentially empty. The threshold could be 100 or 150 with identical results on this corpus.

Alternative considered: carry `fillColor: NSColor` / `textColor: NSColor` continuously. Rejected — adds Phase 2 complexity that U5 shows no benefit for. Easy to upgrade later by widening the field type if a non-monochrome page appears.

### D4. Keep confidence threshold as a named constant

U13 audit: every confirmed false positive has `conf ∈ {0.42, 0.55}`; every true positive has `conf ≥ 0.77`. The data show headroom exists, but the Phase 1 plan does not need to lock in a new value yet.

Implementation: keep `ComicTextDetectorService.confidenceThreshold` as a named `private static let` so the value remains discoverable for tuning in a follow-up change (U15 calibration or later implementation work). This change intentionally does not prescribe the constant's new value.

Alternative considered: dynamic threshold tied to image size or detection density. Rejected — U13 shows the threshold-vs-quality relationship is tight and global; complexity not justified.

### D5. New return type to carry the page-level mask

`MangaOCRService.recognizeAndCluster(in:)` currently returns `[BubbleCluster]`. After this change it returns:

```swift
public struct MangaOCRPageResult {
    public let bubbles: [BubbleCluster]
    public let textPixelMask: CGImage?  // nil if no detections
}
```

Internal-only breaking change. All in-repo callers (`OCRRouter`, batch pipeline, `MangaPage` state machine, OCR benchmark) must be updated. No external API surface.

Alternative considered: keep `[BubbleCluster]` and stash the mask in a separate property on `MangaOCRService` keyed by request. Rejected — request/response coupling is the right model; storing per-request state on the service invites concurrency bugs.

### D6. `BubbleCluster` gains `isInverted: Bool` (Codable, default `false`)

The polarity is per-bubble, not per-page; it belongs on the cluster. Default value preserves binary compatibility with persisted page state in `Models.swift` (the JSON encoder will tolerate the new field on decode if it's optional with a default, or it can be marked `Codable` with a default initializer).

Alternative considered: add `BubblePolarity` enum (`.normal`, `.inverted`, `.unknown`). Rejected — U5's bimodal split makes a third state unnecessary; the cost of an enum is overhead without payoff.

### D7. Benchmark counters are scalar per-image fields

`BenchmarkReporter` already emits per-image structured records. The two new counters slot in alongside existing fields. Naming: `lowConfidenceDetections` (count of detector outputs with `conf < 0.60`, i.e. boxes in the low-confidence band) and `invertedBubbles` (count where `isInverted == true`). Both serve as regression signals for future corpus audits later.

## Risks / Trade-offs

[Risk] The 1.4 % FP rate from U13 is from 17 pages from 2 sources. A more diverse corpus could surface FPs at higher confidence. → Mitigation: keep `confidenceThreshold` as a named constant; the exact cutoff remains a tuning point.

[Risk] The `isInverted` luminance threshold (128) is fixed. A non-monochrome page or a chromatic bubble could trip it. → Mitigation: U5 shows the bimodal gap on monochrome manga is ~250 wide; threshold tolerance is very high. The constant is centrally located for future tuning.

[Risk] The page-level mask increases memory residency for every cached OCR result. → Mitigation: binary at native resolution is small (<100 KB typical); the mask is held only on the page model, which is already loaded with a CGImage of the original. Net incremental cost is one extra binary copy.

[Risk] Downstream callers of `recognizeAndCluster` change signature. → Mitigation: this is internal Swift code; a compile error catches every miss. No SDK / external consumers.

[Risk] U13's low-confidence tail suggests there is room to retune the shared threshold later. → Mitigation: U6's claim was about *per-class* tuning; the roadmap keeps the threshold as a named constant so a later implementation change can adjust it without further spec churn.

## Migration Plan

1. Update `ComicTextDetectorService` to return the `seg` output alongside `[DetectedTextRegion]` (new internal struct).
2. Update `MangaOCRService.recognizeAndCluster(in:)` signature; thread the mask through to the new `MangaOCRPageResult`.
3. Add `isInverted: Bool` to `BubbleCluster`; compute it inside `MangaOCRService` before constructing each cluster.
4. Update all callers (`OCRRouter`, batch pipeline, `MangaPage` state, OCR benchmark, debug viewers). Compiler will surface every site.
5. Keep `confidenceThreshold` as a named constant for now.
6. Add `lowConfidenceDetections` and `invertedBubbles` to `BenchmarkReporter`.
7. Add tests: `isInverted` classifier unit test, `textPixelMask` non-empty unit test, benchmark counter integration test.
8. Run OCRBenchmark on `examples/_verification/u13/` and confirm: zero detections in `book1/008.jpg` and `book1/010.jpg` that were previously labelled FP, and the two corpus inverted-bubble pages (`002.jpg`, `003.jpg`) yield `invertedBubbles >= 5`.

Rollback: revert the conf threshold to `0.4`, revert the return-type widening (single commit, mechanical reversal). The mask CGImage is additive — leaving it produced but unused is harmless.

## Open Questions

- Dilate radius for the mask (current: 3 px). Phase 2 inpainting may want more or less; tunable. Pick 3 to ship, revisit when Phase 2's inpainter is selected (U12).
- Whether the `textPixelMask` should be cached on the `MangaPage` model or recomputed on demand. Recommend cache: it is deterministic from the page image + detector output and Phase 2 will read it frequently.
- Naming: `textPixelMask` vs `inkMask` vs `seg`. The proposal uses `textPixelMask` since downstream code is in Swift, not ONNX-land. Open to feedback.
