## Why

The current `manga-ocr` model is an older version that has limitations in recognizing modern manga fonts, sound effects (SFX), and furigana. Upgrading to the 2025 fine-tuned version will significantly improve OCR accuracy and translation quality.

## What Changes

- Replace `encoder_model.onnx` and `decoder_model.onnx` in `MangaTranslator/Resources/Models/`.
- Update the corresponding `vocab.txt` file.
- Ensure compatibility with the existing `MangaOCRRecognizer.swift`.

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `manga-ocr`: Upgrade underlying model weights and vocabulary to improve recognition accuracy for specialized fonts and layouts.

## Impact

- **Affected Assets**: Model files in `MangaTranslator/Resources/Models/`.
- **Services**: Direct impact on the output quality of `MangaOCRRecognizer.swift`.
- **Testing**: Requires verification through unit tests and manual accuracy checks.
