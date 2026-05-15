## Why

Phase 2 of the manga-translator roadmap will composite translated text directly onto the page image. That render step needs (a) a per-pixel text mask so it knows where the original ink lives, and (b) a polarity flag so it does not paint white text onto a black narration box. Phase 1 verification (ROADMAP §3, U1b/U2/U5/U10/U13) showed the bundled `comic-text-detector.onnx` already produces both signals — the `seg` head is a polarity-agnostic text-pixel mask, and bubble-interior luminance is strongly bimodal (median 253 for normal, ~0 for inverted, near-zero density in between). The verification also showed the model's "out-of-bubble" false-positive rate is only 1.4 % on the 17-page corpus and all of those failures sit below confidence 0.60, while every true positive sits above 0.77 — so a single threshold bump catches the known failures without any per-class tuning, association port, or orphan-filter heuristic.

## What Changes

- Surface the `seg` ONNX output as a page-level binary text-pixel mask (`CGImage`) on the manga-OCR pipeline result.
- Add an `isInverted: Bool` field to each detected bubble, derived from `seg`-masked interior luminance against a fixed threshold.
- Raise the shared detector confidence threshold in `ComicTextDetectorService` from `0.40` to `0.55`.
- Extend the OCR Benchmark report with two new per-image counters: `lowConfidenceDetections` (boxes with `0.40 ≤ conf < 0.60`) and `invertedBubbles` (count where `isInverted == true`).
- **BREAKING (internal):** `MangaOCRService.recognizeAndCluster(in:)` callers receive a new struct that wraps `[BubbleCluster]` plus the page-level text mask, instead of a bare array. Downstream consumers (`Models.MangaPage` state machine, batch pipeline, OCR routing) must accept the new return type.

Out of scope (originally planned for Phase 1 but eliminated by verification):
- Per-class confidence thresholds (`conf_text` / `conf_bubble`) — U6 confirmed no headroom; class 0 is essentially absent in the corpus.
- Port of upstream `group_output` (text-line ↔ bubble association) — U2 confirmed there are no text-class detections to associate.
- Orphan-text filter — same reason; folded into the conf bump.
- Title / SFX heuristic — U13 deferred until corpus diversification (U15) shows a real failure rate.
- Consuming the `det` (DBNet line-level) head — Phase 2's inpaint route does not need it.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `bubble-detection`: gains a page-level text-pixel mask requirement and a per-bubble `isInverted` requirement; the existing "each region → one BubbleCluster" wording is preserved (U2 confirms it is still correct, the model is effectively single-class on our corpus).
- `manga-ocr`: detector confidence threshold requirement clarifies the default value (raised from `0.40` to `0.55`); pipeline return shape adds the page-level text mask.
- `ocr-benchmark`: report adds two per-image counters.

## Impact

- **Code**
  - `MangaTranslator/Services/ComicTextDetectorService.swift` — read `seg` output, return it alongside bounding boxes; update `confidenceThreshold` constant; introduce a small struct that pairs `[DetectedTextRegion]` with the page-level mask.
  - `MangaTranslator/Services/MangaOCRService.swift` — propagate the new result shape; compute `isInverted` per bubble (interior 64×64 sample with seg-text pixels masked, BT.601 luminance < 128).
  - `MangaTranslator/Models/Models.swift` — `BubbleCluster` gains `isInverted: Bool`; new top-level pipeline result wraps `[BubbleCluster]` and `textPixelMask: CGImage`.
  - `MangaTranslator/Views/...` — sidebar viewer remains unchanged; Phase 2 will consume the new mask later.
  - `OCRBenchmarkTests/BenchmarkReporter.swift` — emit the two new counters.
- **Tests**
  - Unit tests for the luminance-based `isInverted` classifier, including a regression fixture for the seven inverted bubbles already in `examples/_verification/u5_data`.
  - Unit test that `ComicTextDetectorService` returns a non-empty mask whose `>0.5` pixel count matches the seg coverage seen in `examples/_verification/u2_u5_u6/corpus_stats.tsv`.
  - Benchmark assertion that the new counters appear in the generated report.
- **Dependencies / models**
  - No new ONNX models. No new external dependencies. The `seg` head was already requested in `ORTSession.run` but its output was discarded — wiring it up is free.
- **Risks**
  - Corpus size for U13's FP-rate finding (1.4 %) is only 17 pages from two sources. The threshold bump may need a second pass if real-world content surfaces FPs at higher confidence. Mitigation: keep the conf threshold as a named constant and add U15 (broader corpus audit) as a follow-up change.
  - The `isInverted` luminance threshold is fixed at 128; U5 shows the bimodal gap is wide enough that this is safe, but the constant should be discoverable for tuning.
