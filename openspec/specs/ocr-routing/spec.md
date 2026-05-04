## Purpose

Routing OCR requests to the appropriate engine based on language and handling fallbacks.

## Requirements

### Requirement: Route OCR based on source language
The system SHALL use the high-accuracy OCR pipeline when the source language is Japanese (.ja), the device is Apple Silicon (`#if arch(arm64)`), the model is downloaded and verified, and the user has enabled high-accuracy OCR in preferences. The system SHALL use the standard manga-ocr ONNX pipeline for Japanese when the high-accuracy model is unavailable or disabled. The system SHALL use the Vision framework OCR pipeline for all other source languages (.en, .zhHant).

#### Scenario: Japanese source language, high-accuracy enabled and model downloaded
- **WHEN** the user has set source language to Japanese, the device is Apple Silicon, the model is downloaded, and high-accuracy OCR is enabled
- **THEN** the system uses `ComicTextDetectorService` + `PaddleOCRVLRecognizer` for text detection and recognition

#### Scenario: Japanese source language, high-accuracy enabled and recognizer fails
- **WHEN** the user has set source language to Japanese, high-accuracy OCR is enabled, and `PaddleOCRVLRecognizer` throws
- **THEN** the system returns a user-visible high-accuracy OCR error and does not execute `MangaOCRRecognizer` or `VisionOCRService`

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
- **THEN** the system uses `VisionOCRService` + `BubbleDetector` for text detection and recognition

#### Scenario: Traditional Chinese source language
- **WHEN** the user has set source language to Traditional Chinese
- **THEN** the system uses `VisionOCRService` + `BubbleDetector` for text detection and recognition

### Requirement: Fallback to Vision OCR on manga-ocr failure only
The system SHALL fall back to the Vision OCR pipeline if the manga-ocr pipeline fails. The system SHALL log a warning when fallback occurs. When high-accuracy OCR is enabled and selected, `PaddleOCRVLRecognizer` failures SHALL be surfaced as explicit errors and SHALL NOT fall back.

#### Scenario: High-accuracy recognizer failure in strict mode
- **WHEN** `PaddleOCRVLRecognizer` throws an error during inference while high-accuracy OCR is enabled
- **THEN** the system surfaces a user-visible error and does not run fallback OCR engines

#### Scenario: Model load failure fallback
- **WHEN** the manga-ocr ONNX models fail to load
- **THEN** the system falls back to `VisionOCRService` and logs a warning

### Requirement: High-accuracy mode requires downloaded model
The system SHALL prevent entering high-accuracy enabled state unless the model is downloaded and verified.

#### Scenario: User tries to enable before download
- **WHEN** the model is not downloaded and the user attempts to enable high-accuracy OCR
- **THEN** enable is rejected, `paddleocr.enabled` remains `false`, and the user is prompted to download first

#### Scenario: Download and Enable flow completes
- **WHEN** the user taps "Download and Enable" and download + verification succeed
- **THEN** `paddleocr.enabled` is set to `true` and routing uses the strict high-accuracy path

#### Scenario: Model becomes unavailable after being enabled
- **WHEN** launch verification or deletion determines the model is unavailable
- **THEN** `paddleocr.enabled` is reset to `false` before routing and the standard manga-ocr path is used

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

## Known Limitations of VisionOCRService

The following limitations are documented for future reference. VisionOCR is a secondary engine (fallback for Japanese, primary for EN/ZH) and not intended to replace MangaOCR for Japanese manga:

- **Bubble segmentation**: VisionOCRService returns individual text-line observations. BubbleDetector clusters these by proximity (distance threshold = 2× median line height). This approach cannot separate adjacent speech bubbles that are physically close on the page. MangaOCR uses a dedicated YOLO-based comic-text-detector trained on manga layouts.
- **Furigana (振り仮名)**: With minimumTextHeightFraction = 0.01, small furigana annotations are now detected. They are merged into the parent bubble cluster by BubbleDetector, producing mixed output (e.g., furigana characters concatenated with the main text). Filtering by relative glyph height is a potential mitigation but is not currently implemented.
- **Reading direction**: ReadingOrderSorter assumes right-to-left column ordering for all content. The `RecognizedTextObservation.Direction` API (leftToRight / rightToLeft / topToBottom) that would enable per-page direction detection requires macOS 26+, which is not the current minimum deployment target (macOS 15).
