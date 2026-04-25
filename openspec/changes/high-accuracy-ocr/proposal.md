## Why

The current OCR pipeline achieves ~27% full-sentence accuracy on manga text. A fine-tuned vision-language model (PaddleOCR-VL-For-Manga) reaches ~70% accuracy on the same benchmark — a 2.6x improvement — and can be run natively on Apple Silicon via MLX without any Python dependency.

## What Changes

- Add a downloadable high-accuracy OCR model (4-bit quantized, ~700MB) for Apple Silicon users
- Add model download, verification, and deletion management
- Add device capability detection (Apple Silicon vs Intel, RAM check)
- Extend OCR routing to use the high-accuracy recognizer when available and enabled
- Add a new settings section for users to download, enable, disable, and delete the model
- Add a model conversion script (Python/uv) included in the repo for reproducibility

## Capabilities

### New Capabilities

- `high-accuracy-ocr`: Download, manage, and use a high-accuracy OCR model on Apple Silicon; includes device capability detection, model lifecycle management (download/verify/delete), and settings UI

### Modified Capabilities

- `ocr-routing`: OCR router gains a new branch for Apple Silicon + high-accuracy model enabled; falls back to existing MangaOCR when model is unavailable or disabled
- `manga-ocr`: MangaOCRService extracts an `OCRRecognizing` protocol so both recognizers share a common interface
- `settings-management`: Settings view gains a new section for high-accuracy OCR management

## Impact

- **New Swift target**: `MangaTranslatorMLX` (arm64-only) to isolate `mlx-swift` dependency from Universal Binary build
- **New SPM dependency**: `mlx-swift` (arm64 target only)
- **New Python tooling**: `scripts/convert_model/` — uv-based environment for one-time model conversion and quantization
- **New storage**: Model downloaded to `~/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL/`
- **Modified files**: `OCRRouter.swift`, `MangaOCRService.swift`, `MangaOCRRecognizer.swift`, `SettingsView.swift`, `MangaTranslatorApp.swift`
