## Purpose

Single owner for the reproducible Python tooling under `scripts/convert_model/` that converts the upstream HuggingFace PaddleOCR-VL model to MLX format, runs quantization sweeps, and performs crop-level BF16-vs-quantized parity verification using detector-aligned crops (or explicit crop manifests). Covers `uv` environment setup, scoped HuggingFace cache location, and complete teardown. Out of scope: app runtime, OCR routing, recognizer memory management, and user-facing error codes.

## Requirements

### Requirement: Provide reproducible model conversion tooling
The repo SHALL include self-contained Python tooling at `scripts/convert_model/` that converts the original HuggingFace model to MLX format, supports quantization parameter sweeps, and benchmarks BF16 vs quantized behavior on crop-based datasets that match the app's OCR flow. The environment SHALL use `uv` and store all downloads in `scripts/convert_model/.hf_cache/`. Running `teardown.sh` SHALL completely remove `.venv/` and `.hf_cache/`, leaving no artifacts outside the project directory.

For verification, `verify.py` SHALL support two crop-oriented inputs:

- `--test-images`: page images that are first passed through the app's `ComicTextDetectorService`, then cropped per detected text region using the same expansion rules as `PaddleOCRVLRecognizer`
- `--crop-manifest`: explicit crop definitions for curated or regression-specific evaluation sets

`verify.py` SHALL NOT treat full pages as direct OCR inference inputs for parity evaluation. Detector-export JSON used for `--test-images` MAY be persisted for debugging, but SHALL be generated automatically by the verification workflow and SHALL NOT require a separate manual preprocessing step.

#### Scenario: Setup and conversion
- **WHEN** a developer runs `setup.sh` followed by `convert.py`
- **THEN** a `.venv/` is created, dependencies are installed, the model is downloaded to `.hf_cache/`, quantized, and written to the requested output directory

#### Scenario: Sweep conversion parameters
- **WHEN** a developer runs the sweep tooling with multiple quantization group sizes
- **THEN** separate MLX outputs and a machine-readable summary report are produced for each tested configuration

#### Scenario: Teardown removes all artifacts
- **WHEN** a developer runs `teardown.sh`
- **THEN** `.venv/` and `.hf_cache/` are fully removed; no files remain in `~/.cache/huggingface/` or other system directories

#### Scenario: Verify detector-driven parity from test images
- **WHEN** `verify.py` is run with `--test-images`
- **THEN** the script invokes App-aligned detector export, prepares crops from detected text regions, runs BF16 and quantized OCR on those crops, and reports parity metrics per region rather than per full page

#### Scenario: Verify parity from explicit crop manifest
- **WHEN** `verify.py` is run with `--crop-manifest`
- **THEN** the script uses the provided crop definitions directly and reports parity metrics per crop

#### Scenario: Full-page OCR is not used for parity
- **WHEN** a developer supplies page images to `verify.py`
- **THEN** the script SHALL NOT send the full page directly to the OCR model for parity evaluation, and SHALL instead verify only detector-derived crops

#### Scenario: Detector output is generated automatically
- **WHEN** a developer runs `verify.py --test-images ...`
- **THEN** no separate manual Swift export command is required before verification begins

#### Scenario: Use crop-level parity as the primary phase0 gate
- **WHEN** developers review phase0 verification output
- **THEN** detector-aligned crop-level BF16 vs quantized parity is treated as the primary go/no-go signal

