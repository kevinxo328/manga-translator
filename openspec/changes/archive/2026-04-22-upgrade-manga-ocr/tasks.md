## 1. Resource Preparation

- [x] 1.1 Download `encoder_model.onnx` (22.4 MB) from `l0wgear/manga-ocr-2025-onnx`
- [x] 1.2 Download `decoder_model.onnx` (118 MB) from `l0wgear/manga-ocr-2025-onnx`
- [x] 1.3 Download `vocab.txt` from `l0wgear/manga-ocr-2025-onnx`

## 2. Deployment

- [x] 2.1 Backup existing model files in `MangaTranslator/Resources/Models/`
- [x] 2.2 Replace `encoder_model.onnx`
- [x] 2.3 Replace `decoder_model.onnx`
- [x] 2.4 Replace `vocab.txt`

## 3. Verification & Testing

- [x] 3.1 Run unit tests to ensure model loading and tokenizer initialization
- [x] 3.2 Perform manual testing with images containing artistic fonts/SFX to verify accuracy improvement
