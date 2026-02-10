## ADDED Requirements

### Requirement: Route OCR based on source language
The system SHALL use the manga-ocr ONNX pipeline when the source language is Japanese (.ja). The system SHALL use the Vision framework OCR pipeline for all other source languages (.en, .zhHant).

#### Scenario: Japanese source language
- **WHEN** the user has set source language to Japanese
- **THEN** the system uses comic-text-detector + manga-ocr for text detection and recognition

#### Scenario: English source language
- **WHEN** the user has set source language to English
- **THEN** the system uses VisionOCRService + BubbleDetector for text detection and recognition

#### Scenario: Traditional Chinese source language
- **WHEN** the user has set source language to Traditional Chinese
- **THEN** the system uses VisionOCRService + BubbleDetector for text detection and recognition

### Requirement: Fallback to Vision OCR on manga-ocr failure
The system SHALL fall back to the Vision OCR pipeline if the manga-ocr pipeline fails (e.g., model loading error). The system SHALL log a warning when fallback occurs.

#### Scenario: Model load failure fallback
- **WHEN** the manga-ocr ONNX models fail to load
- **THEN** the system falls back to VisionOCRService and logs a warning
