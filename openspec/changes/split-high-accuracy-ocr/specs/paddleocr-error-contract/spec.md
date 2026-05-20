## ADDED Requirements

### Requirement: Emit stable PaddleOCR error codes
The system SHALL emit user-visible, categorized errors for strict high-accuracy flows, and each category SHALL map to stable UI messaging and retry guidance. The system SHALL expose stable error codes for UI and telemetry:

- `paddleocr.download_failed`
- `paddleocr.verify_failed`
- `paddleocr.model_unavailable`
- `paddleocr.inference_failed`
- `paddleocr.storage_unavailable`
- `paddleocr.operation_cancelled`

Error code and localization policy:

- Error code is a stable contract key and MUST NOT be used directly as a localization key.
- UI localization keys SHALL be mapped from error code via a dedicated mapping layer.
- Recommended localization key pattern: `error.<error-code>.title` and `error.<error-code>.message` (with `.` replacing separators as needed).

#### Scenario: Model unavailable error
- **WHEN** strict high-accuracy mode is selected but model files are missing or invalid
- **THEN** the system emits `paddleocr.model_unavailable` with guidance to download or re-verify model data

#### Scenario: Verification error
- **WHEN** checksum verification fails for a downloaded artifact
- **THEN** the system emits `paddleocr.verify_failed` and clears invalid download state before retry

#### Scenario: Inference runtime error
- **WHEN** model loading or inference execution fails in strict high-accuracy mode
- **THEN** the system emits `paddleocr.inference_failed` and does not execute fallback OCR engines

#### Scenario: Download transport/storage error
- **WHEN** download fails due to network interruption, cancellation, or insufficient disk/write permissions
- **THEN** the system emits `paddleocr.download_failed` or `paddleocr.storage_unavailable` with actionable retry guidance

#### Scenario: User-cancelled operation error
- **WHEN** a user explicitly cancels an in-progress high-accuracy operation
- **THEN** the system emits `paddleocr.operation_cancelled` and leaves state consistent with cancellation semantics

#### Scenario: Localization text changes do not alter error code contract
- **WHEN** localized message copy is updated
- **THEN** emitted error codes remain unchanged, and only mapped localization keys/messages are modified
