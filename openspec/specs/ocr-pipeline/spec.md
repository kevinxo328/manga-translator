## Purpose

Text recognition from manga images using macOS Vision framework.

## Requirements

### Requirement: Recognize text in manga images
The system SHALL use macOS Vision framework (`VNRecognizeTextRequest`) to detect and recognize text regions in manga images. The system SHALL support Japanese, English, and Traditional Chinese text recognition.

#### Scenario: Japanese manga page with multiple text regions
- **WHEN** user opens a manga image containing Japanese text in speech bubbles
- **THEN** the system detects all text regions and returns their bounding boxes and recognized text strings

#### Scenario: Mixed language text
- **WHEN** a manga image contains both Japanese and English text (e.g., sound effects in English)
- **THEN** the system recognizes text in both languages

### Requirement: Normalize coordinates from Vision to image space
The system SHALL convert Vision framework normalized coordinates (origin at bottom-left, 0-1 range) to image pixel coordinates (origin at top-left). All downstream consumers (bubble detection, UI overlay) SHALL receive coordinates in image space.

#### Scenario: Coordinate conversion
- **WHEN** Vision returns a text observation at normalized rect (0.7, 0.8, 0.2, 0.1) for a 1000x1500 image
- **THEN** the system converts it to image-space rect (x: 700, y: 150, width: 200, height: 150)

### Requirement: Return structured text observations
The system SHALL return an array of text observations, each containing: bounding box (image coordinates), recognized text string, and recognition confidence score.

#### Scenario: Structured output
- **WHEN** OCR processing completes for an image
- **THEN** each result contains a CGRect bounding box, a String of recognized text, and a Float confidence value between 0 and 1
