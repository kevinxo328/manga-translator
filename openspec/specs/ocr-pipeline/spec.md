## Purpose

Text recognition from manga images using macOS Vision framework.

## Requirements

### Requirement: Recognize text in manga images
The system SHALL use the appropriate OCR engine based on source language: manga-ocr ONNX pipeline for Japanese, Vision framework for other languages. The system SHALL support Japanese, English, and Traditional Chinese text recognition. For Japanese, the system SHALL handle both vertical (tategaki) and horizontal text in manga speech bubbles.

#### Scenario: Japanese manga page with vertical text in speech bubbles
- **WHEN** user opens a manga image containing vertical Japanese text in speech bubbles
- **THEN** the system detects all text regions using comic-text-detector and recognizes text using manga-ocr, returning bounding boxes and recognized text strings

#### Scenario: Japanese manga page with horizontal text
- **WHEN** user opens a manga image containing horizontal Japanese text (titles, notes)
- **THEN** the system detects and recognizes the horizontal text correctly

#### Scenario: English or Chinese text
- **WHEN** user opens an image with source language set to English or Traditional Chinese
- **THEN** the system uses Vision framework OCR to detect and recognize text

### Requirement: Vision OCR uses macOS 15 RecognizeTextRequest API
`VisionOCRService` SHALL use the `RecognizeTextRequest` API (macOS 15+) instead of the legacy `VNRecognizeTextRequest`. The macOS 15 API adds support for detecting text direction on each observation, improving results on vertical Japanese text that the legacy API could not handle.

The service SHALL expose configurable properties for `usesLanguageCorrection`, `minimumTextHeightFraction`, and a helper `recognitionLanguages(for:)` that always includes English as a secondary language.

Default configuration:
- `usesLanguageCorrection`: `true` — enables language-model post-processing to correct recognition errors
- `minimumTextHeightFraction`: `0.01` — detects text as small as 1% of image height (the legacy default of 3.125% filtered out furigana, sound effects, and dense tategaki lines)
- `recognitionLanguages`: source language first, always followed by `en-US` for mixed JP/EN content

#### Scenario: Small text detection (furigana, sound effects)
- **WHEN** a manga page contains text smaller than 3% of image height (e.g., furigana, SFX)
- **THEN** VisionOCRService detects those regions (minimumTextHeightFraction = 0.01)

#### Scenario: Mixed JP/EN content
- **WHEN** a page contains both Japanese and English text
- **THEN** VisionOCRService recognizes both because en-US is always included in recognitionLanguages

### Requirement: Normalize coordinates from Vision to image space
The system SHALL convert Vision framework normalized coordinates (origin at bottom-left, 0-1 range) to image pixel coordinates (origin at top-left) when Vision OCR is used. All downstream consumers (bubble detection, UI overlay) SHALL receive coordinates in image space regardless of the OCR engine used.

#### Scenario: Coordinate conversion (Vision)
- **WHEN** Vision returns a text observation at normalized rect (0.7, 0.8, 0.2, 0.1) for a 1000x1500 image
- **THEN** the system converts it to image-space rect (x: 700, y: 150, width: 200, height: 150)

### Requirement: Return structured text observations
The system SHALL return an array of text observations, each containing: bounding box (image coordinates), recognized text string, and recognition confidence score. This contract SHALL be the same regardless of which OCR engine is used.

#### Scenario: Structured output from manga-ocr
- **WHEN** manga-ocr processing completes for an image
- **THEN** each result contains a CGRect bounding box in image coordinates, a String of recognized text, and a Float confidence value between 0 and 1
