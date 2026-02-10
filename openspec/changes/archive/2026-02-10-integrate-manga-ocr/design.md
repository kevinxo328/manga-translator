## Context

The app currently uses Apple's Vision framework for OCR, which fails on vertical Japanese text (tategaki) — the dominant text direction in manga. On a typical manga page, Vision only detects horizontal title bars and misses all dialogue. The bubble detection layer (`BubbleDetector`) also depends on Vision's text observations, so when Vision fails, the entire pipeline fails.

The [Koharu project](https://github.com/mayocream/koharu) has proven that manga-ocr and comic-text-detector ONNX models work well for manga translation in non-Python environments (Rust + ONNX Runtime). We follow the same approach for Swift.

**Current pipeline:**
```
NSImage → VisionOCR → [TextObservation] → BubbleDetector → [BubbleCluster] → Translation
```

**New pipeline (Japanese):**
```
NSImage → ComicTextDetector(ONNX) → [TextRegion] → crop → MangaOCR(ONNX) → [BubbleCluster] → Translation
```

**Fallback pipeline (non-Japanese):**
```
NSImage → VisionOCR → [TextObservation] → BubbleDetector → [BubbleCluster] → Translation
```

## Goals / Non-Goals

**Goals:**
- Accurate OCR for Japanese manga including vertical text, stylized fonts, and furigana
- Offline, on-device inference with no additional user setup (bundled models)
- Preserve existing `TextObservation` / `BubbleCluster` / `TranslatedBubble` data model contract
- Retain Vision OCR as fallback for English and Traditional Chinese

**Non-Goals:**
- Training or fine-tuning models
- Supporting languages other than Japanese with manga-ocr
- GPU/Neural Engine acceleration (CPU inference is sufficient for macOS desktop)
- Inpainting or image editing

## Decisions

### Decision 1: ONNX Runtime over CoreML

**Choice:** Use ONNX Runtime via [microsoft/onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) SPM package.

**Alternatives considered:**
- **CoreML:** Would need manual model conversion from PyTorch. The encoder-decoder architecture of manga-ocr is difficult to convert, and the tokenizer would need a full Swift reimplementation. No known successful conversion exists.
- **Embedded Python:** Would require bundling a Python runtime (~100MB+), complex packaging, and fragile dependency management.

**Rationale:** Pre-converted ONNX models already exist on HuggingFace. ONNX Runtime has an official Swift SPM package. The Koharu project validates this approach works. Avoids tokenizer reimplementation since ONNX Runtime Extensions supports tokenization.

### Decision 2: Two-model pipeline (detection + recognition)

**Choice:** Use comic-text-detector for text region detection, then manga-ocr for text recognition on cropped regions.

**Rationale:** manga-ocr is a recognition-only model — it needs pre-cropped text region images as input. comic-text-detector provides text bounding boxes and text-line segmentation masks purpose-built for manga/comic pages. This replaces both VisionOCR detection AND BubbleDetector clustering in one step.

### Decision 3: OCR routing by source language

**Choice:** Use manga-ocr pipeline when `sourceLanguage == .ja`, fall back to Vision OCR otherwise.

**Rationale:** manga-ocr is trained specifically for Japanese. Vision framework handles English and Traditional Chinese adequately. This keeps existing non-Japanese behavior unchanged and avoids regressions.

### Decision 4: Protocol-based OCR abstraction

**Choice:** Introduce an `OCRService` protocol that both `MangaOCRService` and `VisionOCRService` conform to. `TranslationViewModel` uses an `OCRRouter` that selects the correct implementation.

**Rationale:** Clean separation of concerns. Easy to test each implementation independently. `TranslationViewModel.translatePage()` logic stays largely unchanged — it just calls the router instead of `VisionOCRService` directly.

### Decision 5: Model files bundled in app Resources

**Choice:** Include .onnx model files in `MangaTranslator/Resources/Models/` and add them to the Xcode project bundle.

**Rationale:** Simplest approach for "works out of the box." Models are loaded once at first use and kept in memory. Total ~170MB is acceptable for a macOS desktop app.

## Risks / Trade-offs

- **[App size +170MB]** → Acceptable for macOS. Could later add on-demand model download if needed.
- **[Tokenizer complexity]** → manga-ocr uses a custom tokenizer. Need to verify ONNX Runtime Extensions handles it, or implement a lightweight tokenizer in Swift using the vocab.json from the model. Mitigation: The Koharu Rust crate includes a working tokenizer implementation we can reference.
- **[comic-text-detector preprocessing]** → Model expects specific input size (likely 1024x1024) and normalization. Need to implement image resize + padding + normalization in Swift. Mitigation: Reference Koharu's implementation.
- **[comic-text-detector postprocessing]** → Model outputs raw tensors (bounding boxes + confidence scores + masks). Need to implement NMS and coordinate scaling in Swift. Mitigation: Standard algorithms, well-documented.
- **[First inference latency]** → ONNX model loading may take 1-2 seconds on first use. Mitigation: Lazy initialization, could pre-warm on app launch.
