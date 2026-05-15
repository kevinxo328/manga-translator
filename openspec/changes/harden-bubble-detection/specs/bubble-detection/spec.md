## ADDED Requirements

### Requirement: Per-page text-pixel mask
The system SHALL produce, alongside the bubble clusters for a page, a single page-level binary `CGImage` indicating which pixels of the original page image are text pixels. The mask SHALL be derived from the `seg` head of the `comic-text-detector` ONNX model by thresholding at `0.5`, dilating to compensate for anti-aliased glyph edges, and resampling to the original image resolution. The mask covers all text recognised on the page, including text inside speech bubbles, inverted (white-on-dark) text, and sound-effect text outside any bubble.

#### Scenario: Standard page with several speech bubbles
- **WHEN** the manga-OCR pipeline processes a page containing dialogue and the detector emits bubble regions
- **THEN** the returned page result includes a non-nil `textPixelMask` whose `>0`-pixel positions cover the recognised text glyphs

#### Scenario: Inverted bubble polarity
- **WHEN** the page contains a black-background bubble with white text
- **THEN** the `textPixelMask` covers the white text glyphs the same way it covers black text on a white bubble (polarity-agnostic)

#### Scenario: Page with no detected text
- **WHEN** the detector returns zero bubble regions for a page
- **THEN** the page result's `textPixelMask` is `nil`

### Requirement: Inverted-polarity flag per bubble
The system SHALL set an `isInverted: Bool` field on every `BubbleCluster`. A bubble SHALL be classified as `isInverted == true` when the BT.601 mean luminance of its interior (a centered 64×64 sample with text pixels masked out via the page text mask) is below `128`. Bubbles whose interior contains fewer than 16 non-text pixels SHALL default to `isInverted == false`.

#### Scenario: Normal white bubble
- **WHEN** the detector finds a speech bubble whose interior is the default white manga background
- **THEN** the resulting `BubbleCluster.isInverted` is `false`

#### Scenario: Black narration box with white text
- **WHEN** the detector finds a black-background narration box (mean interior luminance ≈ 0 after text masking)
- **THEN** the resulting `BubbleCluster.isInverted` is `true`

#### Scenario: Bubble interior is entirely text
- **WHEN** a bubble's central 64×64 region is more than 99 % covered by the text-pixel mask
- **THEN** the cluster's `isInverted` is `false` and a diagnostic log entry is emitted

## MODIFIED Requirements

### Requirement: Cluster text observations into speech bubbles
The system SHALL treat each detected text region as one bubble-level OCR unit. Text regions from comic-text-detector are already bubble-level regions, so no additional clustering is needed — each detected region becomes one `BubbleCluster` directly. Each cluster SHALL carry the new `isInverted: Bool` field defined above; defaulting to `false` when the detector returns no usable interior pixels.

#### Scenario: Manga-ocr detected regions
- **WHEN** using manga-ocr pipeline and comic-text-detector returns 5 text regions
- **THEN** the system creates 5 BubbleCluster objects directly, one per detected region, without additional clustering

#### Scenario: Each cluster carries isInverted
- **WHEN** the pipeline returns a non-empty bubble list for a page
- **THEN** every `BubbleCluster` in the list has a defined `isInverted` value derived from its interior luminance
