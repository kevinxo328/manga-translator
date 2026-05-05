## Why

The current `verify.py` still treats full-page OCR as a first-class verification path, but that does not match how the app actually runs PaddleOCR-VL. This inflates noise, hides crop-level regressions, and makes parity results less useful when diagnosing the real "漏東漏西" behavior seen in production.

## What Changes

- Remove full-page OCR verification as a supported verification mode from `scripts/convert_model/verify.py`
- Make `python verify.py --test-images ...` run detector-driven crop verification instead of sending full pages directly to the model
- Reuse the app's `ComicTextDetectorService` to generate text-region boxes before verification
- Apply the same crop expansion rules used by `PaddleOCRVLRecognizer` before OCR inference
- Compare BF16 and quantized outputs per detected text region, with reporting and thresholds centered on region-level parity
- Allow `verify.py` to optionally persist detector output for debugging and reproducibility without requiring a separate manual preprocessing step

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `high-accuracy-ocr`: Update the conversion and parity verification requirements so `verify.py` uses App-aligned detector crops as the primary and only supported image verification path for `--test-images`

## Impact

- Affected code: `scripts/convert_model/verify.py`, `scripts/convert_model/tests/`, `scripts/convert_model/README.md`
- Affected app-side tooling: a new Swift helper/test entry point that exposes `ComicTextDetectorService` output to the verification script
- Affected specs: `openspec/specs/high-accuracy-ocr/spec.md`
- Testing impact: Python verification tests must cover detector-driven crop preparation and Swift-side detector export behavior
