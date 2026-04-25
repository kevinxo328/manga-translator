## MODIFIED Requirements

### Requirement: Route OCR based on source language
The system SHALL use the high-accuracy OCR pipeline when the source language is Japanese (.ja), the device is Apple Silicon (`#if arch(arm64)`), the model is downloaded and verified, and the user has enabled high-accuracy OCR in preferences. The system SHALL use the standard manga-ocr ONNX pipeline for Japanese when the high-accuracy model is unavailable or disabled. The system SHALL use the Vision framework OCR pipeline for all other source languages (.en, .zhHant).

#### Scenario: Japanese source language, high-accuracy enabled and model downloaded
- **WHEN** the user has set source language to Japanese, the device is Apple Silicon, the model is downloaded, and high-accuracy OCR is enabled
- **THEN** the system uses `ComicTextDetectorService` + `PaddleOCRVLRecognizer` for text detection and recognition

#### Scenario: Japanese source language, high-accuracy enabled but model not downloaded
- **WHEN** the user has set source language to Japanese and high-accuracy OCR is enabled but the model has not been downloaded
- **THEN** the system falls back to `ComicTextDetectorService` + `MangaOCRRecognizer`

#### Scenario: Japanese source language, high-accuracy disabled
- **WHEN** the user has set source language to Japanese and high-accuracy OCR is disabled in preferences
- **THEN** the system uses `ComicTextDetectorService` + `MangaOCRRecognizer`

#### Scenario: Japanese source language on Intel
- **WHEN** the user has set source language to Japanese on an Intel Mac
- **THEN** the system uses `ComicTextDetectorService` + `MangaOCRRecognizer`

#### Scenario: English source language
- **WHEN** the user has set source language to English
- **THEN** the system uses `VisionOCRService` + `BubbleDetector` for text detection and recognition

#### Scenario: Traditional Chinese source language
- **WHEN** the user has set source language to Traditional Chinese
- **THEN** the system uses `VisionOCRService` + `BubbleDetector` for text detection and recognition

---

### Requirement: Fallback to Vision OCR on manga-ocr failure
The system SHALL fall back to the Vision OCR pipeline if the primary OCR pipeline (manga-ocr or high-accuracy) fails. The system SHALL log a warning when fallback occurs. If `PaddleOCRVLRecognizer` throws during inference, the system SHALL fall back to `MangaOCRRecognizer` before falling back to Vision OCR.

#### Scenario: High-accuracy recognizer failure fallback
- **WHEN** `PaddleOCRVLRecognizer` throws an error during inference
- **THEN** the system falls back to `MangaOCRRecognizer`, logs a warning, and continues processing

#### Scenario: Model load failure fallback
- **WHEN** the manga-ocr ONNX models fail to load
- **THEN** the system falls back to `VisionOCRService` and logs a warning

---

## ADDED Requirements

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
