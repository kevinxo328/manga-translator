## Why

The current OCR pipeline achieves ~27% full-sentence accuracy on manga text. A fine-tuned vision-language model (PaddleOCR-VL-For-Manga) reaches ~70% accuracy on the same benchmark — a 2.6x improvement — and can be run natively on Apple Silicon via MLX without any Python dependency.

## What Changes

- Add a downloadable high-accuracy OCR model (8-bit quantized, ~1052MB) for Apple Silicon users
- Add model download, verification, and deletion management
- Add device capability detection (Apple Silicon vs Intel, RAM check)
- Extend OCR routing to use the high-accuracy recognizer when available and enabled
- Add a new settings section for users to download, enable, disable, and delete the model
- Add a model conversion script (Python/uv) included in the repo for reproducibility
- Add a two-layer phase0 verification harness: page-level sanity checks plus crop-level parity checks on detector-like text regions
- Add sweep tooling for quantization group size, crop padding, prompt, and token-limit experiments

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
- **New Python tooling**: `scripts/convert_model/` — uv-based environment for one-time model conversion, quantization sweeps, and BF16/quantized parity verification
- **New storage**: Model downloaded to `~/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL/`
- **Modified files**: `OCRRouter.swift`, `MangaOCRService.swift`, `MangaOCRRecognizer.swift`, `SettingsView.swift`, `MangaTranslatorApp.swift`

## Phase 0 Findings

Internal, non-public phase0 experiments led to three conclusions:

- Page-level CER materially overstates recognizer quantization drift
- The shipping gate for phase0 should be crop-level parity, not page-level average CER
- `group_size=64` remains the best default tradeoff between quality and model size for the current internal sample set

These findings are based on exploratory internal samples rather than a public benchmark dataset, so the proposal records the decisions they support rather than treating the raw numbers as long-term source-of-truth metrics.
