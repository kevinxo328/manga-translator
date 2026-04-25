## ADDED Requirements

### Requirement: OCRRecognizing protocol for recognizer abstraction
The system SHALL define an `OCRRecognizing` protocol with a single method `recognizeText(in:region:) throws -> (text: String, confidence: Float)`. Both `MangaOCRRecognizer` and `PaddleOCRVLRecognizer` SHALL conform to this protocol. `MangaOCRService` SHALL depend only on `any OCRRecognizing` rather than a concrete recognizer type.

#### Scenario: MangaOCRRecognizer conforms to protocol
- **WHEN** `MangaOCRService` requests a recognizer
- **THEN** it receives an instance typed as `any OCRRecognizing`, not `MangaOCRRecognizer` directly

#### Scenario: PaddleOCRVLRecognizer conforms to protocol
- **WHEN** high-accuracy OCR is enabled and model is downloaded on Apple Silicon
- **THEN** `MangaOCRService` receives a `PaddleOCRVLRecognizer` instance typed as `any OCRRecognizing`

#### Scenario: Recognizer reset resets to nil
- **WHEN** `MangaOCRService.resetRecognizer()` is called
- **THEN** the internal recognizer is set to `nil` and will be re-initialized on next inference call
