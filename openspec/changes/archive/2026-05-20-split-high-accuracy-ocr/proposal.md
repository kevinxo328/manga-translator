## Why

`high-accuracy-ocr` currently owns device capability, model lifecycle, recognizer runtime, error contract, state-machine, GPU cleanup, and conversion tooling in one large spec. This makes small OCR changes risky because contributors must reason about unrelated lifecycle, runtime, and tooling rules at the same time.

## What Changes

- Split the current monolithic `high-accuracy-ocr` requirements into four narrower capability specs with explicit ownership.
- Introduce `local-model-lifecycle` as the single owner for model download, verification, deletion, launch verification, capability gating, and the `ModelDownloadState` + `paddleocr.enabled` state machine.
- Introduce `paddleocr-recognizer` as the single owner for PaddleOCR-VL inference behavior, lazy load/unload, memory pressure handling, decode termination, input boundaries, UI-critical execution constraints, and page-boundary MLX GPU cache cleanup.
- Introduce `paddleocr-error-contract` as the single owner for stable PaddleOCR error codes and the rule that localization keys/messages are mapped from, but not identical to, those codes.
- Introduce `model-conversion-tooling` as the single owner for `scripts/convert_model/`, crop-oriented parity verification, detector-driven verification inputs, and conversion environment cleanup.
- Keep `high-accuracy-ocr` as a thin umbrella capability that describes the end-to-end feature and references the four owner capabilities instead of duplicating their requirements.
- Preserve all existing scenario semantics, stable error-code strings, persisted `UserDefaults` keys, model storage path, and the deterministic state-machine table.
- No user-visible behavior, public API, model file format, cache key, or runtime algorithm changes are intended in this change.

## Capabilities

### New Capabilities

- `local-model-lifecycle`: Device capability detection, local model download/verification/delete lifecycle, launch verification, state persistence, invalid-state correction, and deterministic lifecycle coordination for `ModelDownloadState` plus `paddleocr.enabled`.
- `paddleocr-recognizer`: PaddleOCR-VL recognizer runtime behavior, OCR inference boundaries, lazy load/reload/unload, memory pressure release, decode loop termination, strict-mode inference semantics, UI responsiveness, regression-output preservation, and MLX GPU cache cleanup after PaddleOCR page attempts.
- `paddleocr-error-contract`: Stable PaddleOCR error-code contract, error categorization, retry-guidance expectations, and the localization mapping policy for high-accuracy OCR failures.
- `model-conversion-tooling`: Reproducible Python/uv conversion tooling, quantization sweeps, crop-level BF16-vs-quantized parity verification, detector-derived crop generation, explicit crop manifests, and teardown requirements.

### Modified Capabilities

- `high-accuracy-ocr`: Replace the monolithic requirements with a thin umbrella description that delegates requirement ownership to `local-model-lifecycle`, `paddleocr-recognizer`, `paddleocr-error-contract`, and `model-conversion-tooling`.

## Impact

- Affects OpenSpec structure under `openspec/specs/` and the `split-high-accuracy-ocr` change artifacts.
- Requires scenario-by-scenario migration from `high-accuracy-ocr/spec.md` into the four new capability specs, with no semantic loss.
- Requires validation for each new or modified capability with `openspec validate --strict`.
- Requires a scenario count and ownership check before archive to confirm every current `high-accuracy-ocr` scenario is moved to exactly one owner spec.
- Existing tests SHALL be mapped to the new owner specs during planning; any missing coverage discovered for lifecycle, recognizer, error contract, or tooling scenarios SHALL be recorded as tasks, not folded into unrelated UI or translation-flow work.
