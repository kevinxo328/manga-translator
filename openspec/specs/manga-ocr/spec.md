## Purpose

On-device manga text detection and recognition using specialized ONNX models.

## Requirements

### Requirement: Load ONNX models from app bundle
The system SHALL load comic-text-detector and manga-ocr ONNX model files from the app's Resources/Models directory at first use. The system SHALL create ONNX Runtime inference sessions and keep them in memory for subsequent calls.

#### Scenario: First model load
- **WHEN** the manga OCR pipeline is invoked for the first time
- **THEN** the system loads both ONNX models from the bundle and creates inference sessions

#### Scenario: Model files missing
- **WHEN** the ONNX model files are not found in the bundle
- **THEN** the system throws a descriptive error and falls back to Vision OCR

### Requirement: Detect text regions using comic-text-detector
The system SHALL preprocess the input image (resize to model input dimensions, normalize pixel values) and run the comic-text-detector ONNX model to produce text region bounding boxes. The system SHALL apply post-processing (confidence filtering, non-maximum suppression) to the raw model output.

#### Scenario: Manga page with multiple speech bubbles
- **WHEN** a manga page image is provided containing 6 speech bubbles
- **THEN** the system returns bounding boxes for each detected text region with coordinates in image pixel space

#### Scenario: Page with no text
- **WHEN** an image with no text regions is provided
- **THEN** the system returns an empty array of text regions

### Requirement: Recognize Japanese text using manga-ocr
The system SHALL crop detected text regions from the original image, preprocess each crop (resize to manga-ocr input dimensions, normalize), and run the manga-ocr ONNX model to produce Japanese text strings. The system SHALL decode model output tokens using the manga-ocr tokenizer vocabulary.

#### Scenario: Vertical Japanese text in speech bubble
- **WHEN** a cropped text region containing vertical Japanese text is provided
- **THEN** the system returns the correctly recognized Japanese text string

#### Scenario: Horizontal Japanese text
- **WHEN** a cropped text region containing horizontal Japanese text (e.g., title bar) is provided
- **THEN** the system returns the correctly recognized Japanese text string

### Requirement: Implement tokenizer for manga-ocr output decoding
The system SHALL include a tokenizer that maps manga-ocr model output token IDs to text characters using the model's vocabulary file (vocab.json). The tokenizer SHALL handle special tokens (BOS, EOS, PAD) and produce clean text output.

#### Scenario: Decode token sequence
- **WHEN** the manga-ocr model outputs a sequence of token IDs [2, 345, 678, 91, 3]
- **THEN** the tokenizer decodes tokens 345, 678, 91 (skipping BOS=2 and EOS=3) to produce the Japanese text string

### Requirement: Produce TextObservation-compatible output
The system SHALL output results as arrays of `TextObservation` (boundingBox, text, confidence) and `BubbleCluster` (boundingBox, text, observations, index) that are compatible with the existing translation pipeline.

#### Scenario: Pipeline integration
- **WHEN** manga OCR processes a page and detects 4 text regions
- **THEN** it produces 4 BubbleCluster objects with bounding boxes in image coordinates, recognized Japanese text, and sequential indices — ready to be passed directly to the translation service
