## Purpose

High-accuracy on-device OCR for Japanese manga text using a quantized MLX model (PaddleOCR-VL) running on Apple Silicon. Covers device capability detection, model download lifecycle, model integrity verification, inference, error contract, state machine, and model conversion tooling.
## Requirements
### Requirement: Delegate high-accuracy OCR ownership to focused capabilities
The high-accuracy OCR feature SHALL remain the feature-level entry point for on-device PaddleOCR-VL OCR. Detailed behavior SHALL be owned by focused capabilities:

- `local-model-lifecycle` owns capability detection, model download, verification, deletion, launch verification, and `ModelDownloadState` plus `paddleocr.enabled` state convergence.
- `paddleocr-recognizer` owns PaddleOCR-VL inference, lazy load/unload, memory pressure handling, decode termination, input boundaries, UI responsiveness, regression-output preservation, and MLX GPU cache cleanup.
- `paddleocr-error-contract` owns stable PaddleOCR error codes and localization mapping policy.
- `model-conversion-tooling` owns reproducible conversion, quantization sweep, and crop-level parity verification tooling.

#### Scenario: Reader follows feature-level high-accuracy OCR ownership
- **WHEN** a contributor needs the detailed contract for any high-accuracy OCR behavior
- **THEN** the contributor can use `high-accuracy-ocr` as the feature-level entry point and follow the delegated owner capability for the specific lifecycle, recognizer, error, or tooling concern

