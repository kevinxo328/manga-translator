## MODIFIED Requirements

### Requirement: Detect text regions using comic-text-detector
The system SHALL preprocess the input image (resize to model input dimensions, normalize pixel values) and run the comic-text-detector ONNX model to produce text region bounding boxes. The system SHALL apply post-processing (confidence filtering, non-maximum suppression) to the raw model output. The confidence filter SHALL default to `0.55`, calibrated from a Phase 1 audit demonstrating that all observed corpus false positives sit below `0.60` and all observed corpus true positives sit at or above `0.77`. The system SHALL also expose the `seg` head of the detector as a page-level text-pixel mask (see the `bubble-detection` spec for the mask contract).

#### Scenario: Manga page with multiple speech bubbles
- **WHEN** a manga page image is provided containing 6 speech bubbles
- **THEN** the system returns bounding boxes for each detected text region with coordinates in image pixel space

#### Scenario: Page with no text
- **WHEN** an image with no text regions is provided
- **THEN** the system returns an empty array of text regions

#### Scenario: Low-confidence detection below default threshold
- **WHEN** the detector emits a candidate bubble with confidence `0.50`
- **THEN** the post-processing pass discards it and the candidate does not appear in the returned regions

### Requirement: Produce TextObservation-compatible output
The system SHALL output results in a page-level container that bundles `[BubbleCluster]` (each with `boundingBox`, `text`, `observations`, `index`, and `isInverted` — see `bubble-detection` spec) together with the optional page-level `textPixelMask: CGImage?`. Individual `TextObservation` records (`boundingBox`, `text`, `confidence`) remain compatible with the existing translation pipeline.

#### Scenario: Pipeline integration with mask
- **WHEN** manga OCR processes a page and detects 4 text regions
- **THEN** it produces a page result containing 4 BubbleCluster objects with bounding boxes in image coordinates, recognized text, sequential indices, an `isInverted` flag, and a non-nil `textPixelMask` for the page

#### Scenario: Pipeline integration with no detections
- **WHEN** manga OCR processes a page on which the detector finds zero regions
- **THEN** the page result contains an empty bubble list and a `nil` `textPixelMask`
