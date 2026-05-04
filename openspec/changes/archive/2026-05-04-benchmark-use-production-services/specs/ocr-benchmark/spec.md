## MODIFIED Requirements

### Requirement: Dual-engine OCR comparison
For each image, the system SHALL invoke the two OCR engines as independent production pipelines and record their outputs separately:
- **MangaOCR path**: call `MangaOCRService.recognizeAndCluster(in:)` directly; the service handles detection and per-region recognition internally
- **Vision path**: call `VisionOCRService.recognizeText(in:)` on the full image, then cluster observations with `BubbleDetector`

After both engines produce their bubble lists, the system SHALL pair results by greedy IoU matching (threshold ≥ 0.5). Bubbles that cannot be paired SHALL be recorded as unmatched for their respective engine.

The benchmark test SHALL contain no detection or image-cropping logic; all such logic resides inside the production services.

#### Scenario: Both engines succeed and regions overlap
- **WHEN** both engines return bubbles and at least one MangaOCR bubble has IoU ≥ 0.5 with a Vision bubble
- **THEN** the report SHALL show the paired results with both texts and their IoU score

#### Scenario: Both engines succeed but regions do not overlap
- **WHEN** a MangaOCR bubble has IoU < 0.5 with every Vision bubble
- **THEN** that bubble SHALL appear in the unmatched MangaOCR section of the report

#### Scenario: One engine fails
- **WHEN** one engine throws an error or returns no bubbles for an image
- **THEN** the report SHALL show all results from the successful engine as unmatched, and record a failure indicator for the other engine

## ADDED Requirements

### Requirement: Unmatched region reporting
The report SHALL include a section per image listing bubbles that could not be paired across engines. Unmatched MangaOCR bubbles and unmatched Vision bubbles SHALL be listed separately with their bounding box and recognised text.

#### Scenario: Unmatched MangaOCR bubbles
- **WHEN** a MangaOCR bubble has no corresponding Vision bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it under an `[Unmatched MangaOCR]` heading with its bounding box and text

#### Scenario: Unmatched Vision bubbles
- **WHEN** a Vision bubble has no corresponding MangaOCR bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it under an `[Unmatched Vision]` heading with its bounding box and text

#### Scenario: No unmatched bubbles
- **WHEN** every bubble from both engines is paired
- **THEN** the unmatched sections SHALL be omitted from the report

### Requirement: Summary counts reflect independent pipelines
The summary section SHALL report: total paired regions, total unmatched MangaOCR regions, total unmatched Vision regions, and per-engine failure count (images where the engine produced no output).

#### Scenario: Summary correctness
- **WHEN** the report is generated
- **THEN** paired + unmatched MangaOCR count SHALL equal total MangaOCR bubbles found, and paired + unmatched Vision count SHALL equal total Vision bubbles found
