## 1. Dependencies & Model Setup

- [x] 1.1 Add onnxruntime-swift-package-manager SPM dependency to the Xcode project
- [x] 1.2 Download comic-text-detector ONNX model from HuggingFace and add to MangaTranslator/Resources/Models/
- [x] 1.3 Download manga-ocr ONNX model and vocab.json from HuggingFace and add to MangaTranslator/Resources/Models/
- [x] 1.4 Verify ONNX Runtime imports and model files load correctly in a minimal test

## 2. Comic Text Detector (Text Region Detection)

- [x] 2.1 Create ComicTextDetectorService with ONNX session initialization (lazy load from bundle)
- [x] 2.2 Implement image preprocessing: resize to model input dimensions, normalize pixel values, convert to ONNX tensor
- [x] 2.3 Implement inference: run comic-text-detector model and extract raw output tensors
- [x] 2.4 Implement postprocessing: parse bounding boxes, apply confidence threshold filtering, apply NMS, scale coordinates back to original image size

## 3. Manga OCR (Text Recognition)

- [x] 3.1 Create MangaOCRTokenizer that loads vocab.json and decodes token ID sequences to text (handling BOS/EOS/PAD special tokens)
- [x] 3.2 Create MangaOCRRecognizer with ONNX session initialization (lazy load from bundle)
- [x] 3.3 Implement image preprocessing: crop text regions from original image, resize to manga-ocr input dimensions, normalize
- [x] 3.4 Implement inference: run manga-ocr encoder-decoder model with autoregressive decoding loop
- [x] 3.5 Implement output decoding: convert token IDs to Japanese text using MangaOCRTokenizer

## 4. Pipeline Integration

- [x] 4.1 Create MangaOCRService that orchestrates: ComicTextDetector → crop regions → MangaOCRRecognizer → [BubbleCluster]
- [x] 4.2 Create OCRRouter that selects MangaOCRService (Japanese) or VisionOCRService+BubbleDetector (other languages) based on source language
- [x] 4.3 Add fallback logic: if MangaOCRService fails, fall back to VisionOCRService with warning log
- [x] 4.4 Modify TranslationViewModel.translatePage() to use OCRRouter instead of direct VisionOCRService + BubbleDetector calls

## 5. Testing & Validation

- [ ] 5.1 Test manga-ocr pipeline with the test_image.jpg (One Piece page) — verify vertical text is detected and recognized
- [x] 5.2 Test Vision OCR fallback with English source language — verify existing behavior is preserved (code review: OCRRouter routes non-ja to VisionOCRService, no changes to Vision path)
- [x] 5.3 Test model loading failure gracefully falls back to Vision OCR (code review: OCRRouter catches errors and falls back)
- [ ] 5.4 Verify end-to-end: OCR → translation pipeline works with manga-ocr output
