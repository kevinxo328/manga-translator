## Why

The current OCR pipeline relies entirely on Apple's Vision framework (`VNRecognizeTextRequest`), which performs poorly on manga-specific text — especially vertical (tategaki) Japanese text in speech bubbles, stylized fonts, and small furigana. On a typical manga page, Vision only picks up horizontal title bars and editor notes, missing nearly all dialogue. A manga-specialized OCR solution is needed to make the app functional for its primary use case.

## What Changes

- Add ONNX Runtime as a dependency via Swift Package Manager (`microsoft/onnxruntime-swift-package-manager`)
- Bundle two pre-converted ONNX models:
  - **comic-text-detector** (~50MB) — detects text regions and speech bubbles in manga pages
  - **manga-ocr** (~100MB) — recognizes Japanese text from cropped text regions
- Introduce a new `MangaOCRService` that orchestrates: text detection → crop regions → OCR recognition
- Replace the current `VisionOCRService` as the default OCR engine for Japanese source language
- Retain `VisionOCRService` as fallback for non-Japanese languages (English, Traditional Chinese)
- Simplify or bypass `BubbleDetector` when using manga-ocr pipeline, since comic-text-detector already provides bubble-level regions

## Capabilities

### New Capabilities
- `manga-ocr`: ONNX-based manga text detection and recognition pipeline, including model loading, image preprocessing, inference, and tokenizer decoding
- `ocr-routing`: Logic to select the appropriate OCR engine (manga-ocr vs Vision) based on source language setting

### Modified Capabilities
- `ocr-pipeline`: The OCR pipeline contract changes — when manga-ocr is active, text detection and recognition are handled by ONNX models instead of Vision framework. The output format (TextObservation with boundingBox, text, confidence) remains the same.
- `bubble-detection`: When comic-text-detector is used, bubble regions come directly from the model output rather than agglomerative clustering of Vision observations. The BubbleCluster output format remains the same.

## Impact

- **Dependencies**: New SPM dependency on `onnxruntime-swift-package-manager` (~20-30MB framework)
- **App bundle size**: Increases by ~170-180MB (ONNX Runtime + two model files)
- **Code**: New service files for ONNX inference; modifications to `TranslationViewModel` to use OCR routing
- **Models**: Two .onnx files bundled in `MangaTranslator/Resources/`
- **Existing behavior**: No breaking changes — Vision OCR path remains available as fallback
