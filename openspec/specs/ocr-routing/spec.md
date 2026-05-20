## Purpose

Routing OCR requests to the appropriate engine based on model availability and user preference.

## Requirements

### Requirement: Route OCR based on source language
The system SHALL use the high-accuracy OCR pipeline when the device is Apple Silicon (`#if arch(arm64)`), the model is downloaded and verified, and the user has enabled high-accuracy OCR in preferences. Otherwise, the system SHALL use the standard manga-ocr ONNX pipeline. This routing rule SHALL apply to all supported source languages (`.ja`, `.en`).

#### Scenario: Japanese source language, high-accuracy enabled and model downloaded
- **WHEN** the user has set source language to Japanese, the device is Apple Silicon, the model is downloaded, and high-accuracy OCR is enabled
- **THEN** the system uses `ComicTextDetectorService` + `PaddleOCRVLRecognizer` for text detection and recognition

#### Scenario: Japanese source language, high-accuracy enabled and recognizer fails
- **WHEN** the user has set source language to Japanese, high-accuracy OCR is enabled, and `PaddleOCRVLRecognizer` throws
- **THEN** the system returns a user-visible high-accuracy OCR error and does not execute `MangaOCRRecognizer`

#### Scenario: Japanese source language, model not downloaded
- **WHEN** the user has set source language to Japanese and the model has not been downloaded
- **THEN** the system uses `ComicTextDetectorService` + `MangaOCRRecognizer`

#### Scenario: Japanese source language, high-accuracy disabled
- **WHEN** the user has set source language to Japanese and high-accuracy OCR is disabled in preferences
- **THEN** the system uses `ComicTextDetectorService` + `MangaOCRRecognizer`

#### Scenario: Japanese source language on Intel
- **WHEN** the user has set source language to Japanese on an Intel Mac
- **THEN** the system uses `ComicTextDetectorService` + `MangaOCRRecognizer`

#### Scenario: English source language
- **WHEN** the user has set source language to English
- **THEN** the system applies the same PaddleOCR/MangaOCR routing rule used for Japanese

### Requirement: No fallback OCR engine after manga-ocr failure
The system SHALL NOT fall back to a secondary OCR engine when the manga-ocr pipeline fails. When high-accuracy OCR is enabled and selected, `PaddleOCRVLRecognizer` failures SHALL be surfaced as explicit errors and SHALL NOT fall back.

#### Scenario: High-accuracy recognizer failure in strict mode
- **WHEN** `PaddleOCRVLRecognizer` throws an error during inference while high-accuracy OCR is enabled
- **THEN** the system surfaces a user-visible error and does not run fallback OCR engines

#### Scenario: Model load failure
- **WHEN** the manga-ocr ONNX models fail to load
- **THEN** the system surfaces the error without running another OCR engine

### Requirement: Routing honors local-model-lifecycle state
The state machine governing `paddleocr.enabled` and `ModelDownloadState` is owned by `local-model-lifecycle` (see its "Enforce deterministic local model state machine" requirement). Routing SHALL observe whatever value `local-model-lifecycle` has converged to before making each routing decision: when `paddleocr.enabled` is `true` and the model is `.downloaded`, routing uses the strict high-accuracy path; otherwise routing uses the standard manga-ocr path.

#### Scenario: Routing falls back after model becomes unavailable
- **WHEN** `local-model-lifecycle` resets `paddleocr.enabled` to `false` because launch verification or deletion determined the model is unavailable
- **THEN** the next routing decision uses the standard manga-ocr path

### Requirement: Reset recognizer on engine switch
The system SHALL reset the active recognizer instance when the user toggles high-accuracy OCR in preferences or deletes the model, so that the next inference uses the correct recognizer.

#### Scenario: User enables high-accuracy OCR
- **WHEN** the user enables high-accuracy OCR in Settings while a translation is not in progress
- **THEN** `MangaOCRService` resets its recognizer so the next inference uses `PaddleOCRVLRecognizer`

#### Scenario: User deletes model while high-accuracy enabled
- **WHEN** the user deletes the model via Settings
- **THEN** high-accuracy OCR preference is set to `false` and `MangaOCRService` resets its recognizer to `MangaOCRRecognizer`

#### Scenario: Empty image input (boundary)
- **WHEN** an image with zero-area dimensions is passed to the OCR router
- **THEN** the system returns an empty `BubbleCluster` array without crashing

#### Scenario: Very small image input (boundary)
- **WHEN** a 1×1 pixel image is passed to the OCR router
- **THEN** the system returns an empty `BubbleCluster` array without crashing
