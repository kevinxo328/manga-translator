## Purpose

Routing OCR requests to the appropriate engine based on language and handling fallbacks.

## Requirements

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

## Known Limitations of VisionOCRService

The following limitations are documented for future reference. VisionOCR is a secondary engine (fallback for Japanese, primary for EN/ZH) and not intended to replace MangaOCR for Japanese manga:

- **Bubble segmentation**: VisionOCRService returns individual text-line observations. BubbleDetector clusters these by proximity (distance threshold = 2× median line height). This approach cannot separate adjacent speech bubbles that are physically close on the page. MangaOCR uses a dedicated YOLO-based comic-text-detector trained on manga layouts.
- **Furigana (振り仮名)**: With minimumTextHeightFraction = 0.01, small furigana annotations are now detected. They are merged into the parent bubble cluster by BubbleDetector, producing mixed output (e.g., furigana characters concatenated with the main text). Filtering by relative glyph height is a potential mitigation but is not currently implemented.
- **Reading direction**: ReadingOrderSorter assumes right-to-left column ordering for all content. The `RecognizedTextObservation.Direction` API (leftToRight / rightToLeft / topToBottom) that would enable per-page direction detection requires macOS 26+, which is not the current minimum deployment target (macOS 15).
