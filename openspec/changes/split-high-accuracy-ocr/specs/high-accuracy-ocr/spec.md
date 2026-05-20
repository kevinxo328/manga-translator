## ADDED Requirements

### Requirement: Delegate high-accuracy OCR ownership to focused capabilities
The high-accuracy OCR feature SHALL remain the feature-level entry point for on-device PaddleOCR-VL OCR. Detailed behavior SHALL be owned by focused capabilities:

- `local-model-lifecycle` owns capability detection, model download, verification, deletion, launch verification, and `ModelDownloadState` plus `paddleocr.enabled` state convergence.
- `paddleocr-recognizer` owns PaddleOCR-VL inference, lazy load/unload, memory pressure handling, decode termination, input boundaries, UI responsiveness, regression-output preservation, and MLX GPU cache cleanup.
- `paddleocr-error-contract` owns stable PaddleOCR error codes and localization mapping policy.
- `model-conversion-tooling` owns reproducible conversion, quantization sweep, and crop-level parity verification tooling.

#### Scenario: Reader follows feature-level high-accuracy OCR ownership
- **WHEN** a contributor needs the detailed contract for any high-accuracy OCR behavior
- **THEN** the contributor can use `high-accuracy-ocr` as the feature-level entry point and follow the delegated owner capability for the specific lifecycle, recognizer, error, or tooling concern

## REMOVED Requirements

### Requirement: Detect device capability for high-accuracy OCR
**Reason**: Capability detection is owned by `local-model-lifecycle`.
**Migration**: Use `local-model-lifecycle` requirement `Detect local model capability`.

#### Scenario: Device capability scenarios moved to lifecycle owner
- **WHEN** a device capability scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Download high-accuracy OCR model on demand
**Reason**: Download behavior is owned by `local-model-lifecycle`.
**Migration**: Use `local-model-lifecycle` requirement `Download local model on demand`.

#### Scenario: Download scenarios moved to lifecycle owner
- **WHEN** a model download scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Verify model integrity on app launch
**Reason**: Launch verification behavior is owned by `local-model-lifecycle`.
**Migration**: Use `local-model-lifecycle` requirement `Verify local model integrity on app launch`.

#### Scenario: Launch verification scenarios moved to lifecycle owner
- **WHEN** a launch verification scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Delete high-accuracy OCR model
**Reason**: Model deletion behavior is owned by `local-model-lifecycle`.
**Migration**: Use `local-model-lifecycle` requirement `Delete local model`.

#### Scenario: Delete scenarios moved to lifecycle owner
- **WHEN** a model delete scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Run high-accuracy OCR inference on Apple Silicon
**Reason**: Runtime inference behavior is owned by `paddleocr-recognizer`.
**Migration**: Use `paddleocr-recognizer` requirement `Run PaddleOCR-VL recognition on Apple Silicon`.

#### Scenario: Runtime inference scenarios moved to recognizer owner
- **WHEN** a PaddleOCR runtime scenario is needed
- **THEN** the scenario is specified by `paddleocr-recognizer`

### Requirement: Stable decode termination for high-accuracy OCR
**Reason**: Decode termination behavior is owned by `paddleocr-recognizer`.
**Migration**: Use `paddleocr-recognizer` requirement `Stop unstable PaddleOCR decode output deterministically`.

#### Scenario: Decode termination scenarios moved to recognizer owner
- **WHEN** a decode termination scenario is needed
- **THEN** the scenario is specified by `paddleocr-recognizer`

### Requirement: High-accuracy OCR error contract
**Reason**: Error codes and localization policy are owned by `paddleocr-error-contract`.
**Migration**: Use `paddleocr-error-contract` requirement `Emit stable PaddleOCR error codes`.

#### Scenario: Error contract scenarios moved to error-contract owner
- **WHEN** a PaddleOCR error contract scenario is needed
- **THEN** the scenario is specified by `paddleocr-error-contract`

### Requirement: Deterministic high-accuracy state machine
**Reason**: The state machine is owned by `local-model-lifecycle`.
**Migration**: Use `local-model-lifecycle` requirement `Enforce deterministic local model state machine`.

#### Scenario: State-machine scenarios moved to lifecycle owner
- **WHEN** a model lifecycle state-machine scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Reproducible model conversion script
**Reason**: Conversion tooling is owned by `model-conversion-tooling`.
**Migration**: Use `model-conversion-tooling` requirement `Provide reproducible model conversion tooling`.

#### Scenario: Conversion tooling scenarios moved to tooling owner
- **WHEN** a model conversion or parity verification tooling scenario is needed
- **THEN** the scenario is specified by `model-conversion-tooling`

### Requirement: Clear MLX GPU buffer cache after PaddleOCR page processing
**Reason**: PaddleOCR page-processing cleanup is owned by `paddleocr-recognizer`.
**Migration**: Use `paddleocr-recognizer` requirement `Clear MLX GPU buffer cache after PaddleOCR page processing`.

#### Scenario: MLX GPU cache cleanup scenarios moved to recognizer owner
- **WHEN** a PaddleOCR GPU cache cleanup scenario is needed
- **THEN** the scenario is specified by `paddleocr-recognizer`
