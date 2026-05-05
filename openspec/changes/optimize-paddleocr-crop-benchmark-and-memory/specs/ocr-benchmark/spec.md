## MODIFIED Requirements

### Requirement: Dual-engine OCR comparison
For each image, the system SHALL invoke three OCR engines as independent production pipelines and record their outputs separately:

- **PaddleOCR path**: process the image through the production Japanese OCR path that uses `PaddleOCRVLRecognizer` for region recognition
- **MangaOCR path**: call `MangaOCRService.recognizeAndCluster(in:)` directly; the service handles detection and per-region recognition internally
- **Vision path**: call `VisionOCRService.recognizeText(in:)` on the full image, then cluster observations with `BubbleDetector`

After the engines produce their bubble lists, the system SHALL compare them through two greedy IoU matching passes (threshold ≥ 0.5):

- PaddleOCR vs MangaOCR
- PaddleOCR vs Vision OCR

Bubbles that cannot be paired in a given comparison SHALL be recorded as unmatched for that comparison. The benchmark test SHALL contain no direct image-cropping logic and SHALL NOT invoke the PaddleOCR full-page engine path.

#### Scenario: PaddleOCR and MangaOCR produce overlapping regions
- **WHEN** PaddleOCR and MangaOCR both return bubbles and at least one PaddleOCR bubble has IoU ≥ 0.5 with a MangaOCR bubble
- **THEN** the report SHALL show the paired PaddleOCR/MangaOCR result with both texts and the IoU score

#### Scenario: PaddleOCR and Vision produce overlapping regions
- **WHEN** PaddleOCR and Vision OCR both return bubbles and at least one PaddleOCR bubble has IoU ≥ 0.5 with a Vision bubble
- **THEN** the report SHALL show the paired PaddleOCR/Vision result with both texts and the IoU score

#### Scenario: A comparison has no overlapping regions
- **WHEN** all PaddleOCR bubbles have IoU < 0.5 against every bubble from the compared engine
- **THEN** the report SHALL record all PaddleOCR bubbles and all compared-engine bubbles as unmatched for that comparison

#### Scenario: Full-page engine benchmark is excluded
- **WHEN** the OCR benchmark suite runs
- **THEN** it SHALL NOT call `DefaultPaddleOCREngine.infer(image:)` with a full-page source image as a benchmark path

### Requirement: Unmatched region reporting
The report SHALL include unmatched-region sections for each PaddleOCR comparison independently. Unmatched PaddleOCR bubbles, unmatched MangaOCR bubbles, and unmatched Vision bubbles SHALL be listed under their corresponding comparison sections with bounding box and recognised text.

#### Scenario: Unmatched PaddleOCR bubble in PaddleOCR vs MangaOCR
- **WHEN** a PaddleOCR bubble has no corresponding MangaOCR bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it in the unmatched PaddleOCR section for the PaddleOCR/MangaOCR comparison

#### Scenario: Unmatched MangaOCR bubble
- **WHEN** a MangaOCR bubble has no corresponding PaddleOCR bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it in the unmatched MangaOCR section for the PaddleOCR/MangaOCR comparison

#### Scenario: Unmatched Vision bubble
- **WHEN** a Vision bubble has no corresponding PaddleOCR bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it in the unmatched Vision section for the PaddleOCR/Vision comparison

#### Scenario: No unmatched bubbles in a comparison
- **WHEN** every bubble in a comparison is paired
- **THEN** the unmatched sections for that comparison SHALL be omitted

### Requirement: Summary counts reflect independent pipelines
The summary section SHALL report:

- total PaddleOCR vs MangaOCR paired regions
- total PaddleOCR vs Vision paired regions
- unmatched PaddleOCR regions per comparison
- unmatched MangaOCR regions
- unmatched Vision regions
- per-engine image failure counts for PaddleOCR, MangaOCR, and Vision OCR

#### Scenario: Summary correctness for PaddleOCR vs MangaOCR
- **WHEN** the report is generated
- **THEN** paired + unmatched PaddleOCR count for the PaddleOCR/MangaOCR comparison SHALL equal total PaddleOCR bubbles considered in that comparison, and paired + unmatched MangaOCR count SHALL equal total MangaOCR bubbles

#### Scenario: Summary correctness for PaddleOCR vs Vision
- **WHEN** the report is generated
- **THEN** paired + unmatched PaddleOCR count for the PaddleOCR/Vision comparison SHALL equal total PaddleOCR bubbles considered in that comparison, and paired + unmatched Vision count SHALL equal total Vision bubbles

#### Scenario: Engine failure count
- **WHEN** an engine produces no output for an image
- **THEN** the summary SHALL increment that engine's image failure count without masking successful outputs from the other engines

## ADDED Requirements

### Requirement: Per-engine latency reporting
The benchmark report SHALL record per-image latency for each production OCR engine path that runs on that image.

#### Scenario: Successful tri-engine run
- **WHEN** PaddleOCR, MangaOCR, and Vision OCR all complete for an image
- **THEN** the report SHALL include latency entries for each engine on that image

#### Scenario: Engine failure after timing starts
- **WHEN** an engine fails after benchmark timing has started
- **THEN** the report SHALL record the failure and MAY omit latency for that engine if no completed measurement is available
