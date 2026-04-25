## Context

The app currently runs two OCR pipelines:
- **Japanese**: `ComicTextDetectorService` (YOLOv5 ONNX) → `MangaOCRRecognizer` (encoder/decoder ONNX via OnnxRuntimeBindings)
- **Other languages**: Apple Vision framework

All ONNX models are bundled in the app (~224MB total). The app is a Universal Binary (arm64 + x86_64). The new high-accuracy OCR is powered by an 8-bit quantized MLX model (~1052MB), which is only feasible on Apple Silicon via `mlx-swift`. (4-bit quantization produces only newlines for this model architecture and is unusable.) Intel users continue using the existing pipeline unchanged.

## Goals / Non-Goals

**Goals:**
- Let Apple Silicon users opt into a higher-accuracy OCR model
- Keep Intel users fully functional with no regressions
- Keep the app install size unchanged (model downloaded on demand)
- Make the conversion pipeline reproducible and self-contained in the repo

**Non-Goals:**
- Replacing the ComicTextDetectorService (text region detection stays as-is)
- Supporting Intel Mac users for the high-accuracy model
- Automatic model updates (user manually re-downloads if a new version ships)
- Supporting languages other than Japanese with the new model

## Decisions

### D1: Separate arm64-only Swift target for MLX

`mlx-swift` cannot compile for x86_64. Adding it directly to the main target would break Universal Binary builds.

**Decision**: Create a separate `MangaTranslatorMLX` Swift target with `ARCHS = arm64` in build settings. The main app target conditionally links this target and wraps all usage in `#if arch(arm64)`.

**Alternative considered**: Wrapping all MLX imports in `#if arch(arm64)` in the main target. Rejected because SPM still attempts to compile the package for x86_64, causing build failures.

---

### D2: Keep ComicTextDetectorService in the pipeline

PaddleOCR-VL-For-Manga is trained on cropped text regions (same as current MangaOCR), not full-page images. Replacing the detector would require significant re-architecture of the BubbleCluster output format.

**Decision**: `PaddleOCRVLRecognizer` replaces only `MangaOCRRecognizer` in the pipeline. `ComicTextDetectorService` remains unchanged.

---

### D3: OCRRecognizing protocol for recognizer abstraction

`MangaOCRService` currently hardcodes `MangaOCRRecognizer`. To support runtime switching between recognizers, extract a protocol.

**Decision**: Introduce `OCRRecognizing` protocol with `recognizeText(in:region:) throws -> (text: String, confidence: Float)`. Both `MangaOCRRecognizer` and `PaddleOCRVLRecognizer` conform to it. `MangaOCRService` depends only on the protocol.

---

### D4: System memory pressure drives model lifecycle

Even on 16GB machines, simultaneous workloads can exhaust RAM. A fixed "always loaded" or "always unloaded" policy is suboptimal.

**Decision**: `PaddleOCRVLRecognizer` lazy-loads the model on first inference and subscribes to `NSApplication.didReceiveMemoryWarningNotification`. On receiving a warning, the model is released (`model = nil`). The next inference triggers a reload.

**Alternative considered**: Per-device RAM thresholds (≥16GB = always loaded, 8GB = always unload). Rejected because RAM usage depends on what else is running, not just total RAM.

---

### D5: Model download to Application Support, not app bundle

Bundling a ~1052MB model would increase the app download size unacceptably.

**Decision**: Model files live in `~/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL/`. Download is triggered by user action in Settings. SHA256 checksum verified after download. `UserDefaults` tracks download state and checksum.

---

### D6: Isolated Python environment for model conversion

The conversion script is a one-time operation but must be reproducible by any contributor.

**Decision**: `scripts/convert_model/` contains a `uv`-based environment. `HF_HOME` is redirected to `scripts/convert_model/.hf_cache/` so all downloads stay local. `teardown.sh` removes `.venv/` and `.hf_cache/` completely. Output models are not committed to git.

---

### D7: User-initiated download with device gate

Download is only available on Apple Silicon. On 8GB devices, a warning is shown but download is not blocked.

**Decision**: `DeviceCapabilityService` returns `.supported`, `.supportedWithWarning(ram:)`, or `.unsupported`. The Settings UI hides the section on `.unsupported`, shows a warning label on `.supportedWithWarning`, and shows no warning on `.supported`.

## Risks / Trade-offs

- **mlx-community/paddleocr-vl.swift is early-stage (2 commits)** → Mitigation: Treat as reference only; implement `PaddleOCRVLRecognizer` from scratch using `mlx-swift` directly
- **Model conversion may fail due to custom architecture** → Mitigation: Validate conversion output against original model on 5 test images before proceeding to Swift integration; abort Phase 1 if CER delta > 5%
- **First inference is slow after memory pressure release** → Trade-off accepted; user experience degrades gracefully rather than crashing
- **HuggingFace connectivity issues (region-specific)** → Mitigation: Surface clear error messages; consider adding a mirror URL field in a future iteration
- **SHA256 mismatch on partial download** → Mitigation: `ModelDownloadService` deletes partial files and resets state to `.notDownloaded` on checksum failure

## Migration Plan

No data migration required. The feature is additive:
1. Ship app update — existing users see no change
2. Apple Silicon users see new Settings section
3. Users opt in by tapping "Download and Enable"
4. To roll back: user taps "Delete Model Data" — app returns to MangaOCR pipeline

## Open Questions

- ~~Final quantized model size~~ **Resolved: 1051.7 MB (8-bit, SHA256 `a9654f592cd82c18e0e1f7f997a38c6bd09d412a091e7bfd08365d6fbe06c71a`)**
- HuggingFace repo URL for the quantized model (to be set up in Task 0.8)
- Whether `mlx-swift` requires a minimum macOS version beyond macOS 14 (verify during Phase 1 setup)
