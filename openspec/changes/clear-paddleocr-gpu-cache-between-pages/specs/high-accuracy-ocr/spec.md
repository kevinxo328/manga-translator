## ADDED Requirements

### Requirement: Clear MLX GPU buffer cache after PaddleOCR page processing
The system SHALL clear MLX GPU buffer cache after each production high-accuracy PaddleOCR page processing attempt completes. This cleanup SHALL run at the page boundary after PaddleOCR recognition finishes or fails. The cleanup SHALL NOT unload the cached PaddleOCR recognizer/model instance and SHALL NOT change the model's per-generation KV cache behavior.

#### Scenario: Successful PaddleOCR page clears GPU buffer cache
- **WHEN** the production PaddleOCR page path completes successfully
- **THEN** the system clears MLX GPU buffer cache once after the page attempt
- **THEN** the PaddleOCR recognizer/model instance remains reusable for a later page

#### Scenario: Failed PaddleOCR page clears GPU buffer cache
- **WHEN** the production PaddleOCR page path fails with a PaddleOCR error or unexpected OCR error
- **THEN** the system clears MLX GPU buffer cache once after the failed page attempt
- **THEN** the original OCR error remains the error surfaced to the caller

#### Scenario: Standard MangaOCR path does not clear PaddleOCR GPU cache
- **WHEN** the standard MangaOCR path processes a page without using PaddleOCR
- **THEN** the PaddleOCR MLX GPU buffer cache cleanup hook is not invoked
