# OCR Benchmark

## Purpose

The OCR Benchmark capability provides a standalone diagnostic tool that runs both MangaOCR and VisionOCR engines side by side on a set of sample images and produces a plain-text report. It is intended for development and quality evaluation — not for production use.

## Requirements

### Requirement: Image discovery
The system SHALL recursively scan all files under the `examples/` directory and collect images with extensions `.jpg`, `.jpeg`, or `.png` (case-insensitive), regardless of subdirectory depth.

#### Scenario: Images found at multiple depths
- **WHEN** `examples/` contains images at root level and inside subdirectories
- **THEN** all images are collected and processed

#### Scenario: No images found
- **WHEN** `examples/` contains no supported image files
- **THEN** the report SHALL contain a warning message indicating no images were found, and no further processing occurs

### Requirement: Bounding box overlap detection
The system SHALL compute Intersection over Union (IoU) for every pair of detected bounding boxes within the same image. Any box with IoU > 0.5 against another box SHALL be flagged as a suspected overlapping box.

#### Scenario: Large box enclosing smaller boxes
- **WHEN** a detected region has IoU > 0.5 with one or more other regions
- **THEN** the larger box (by area) SHALL be marked with a warning listing all overlapping region indices and their IoU values

#### Scenario: No overlapping boxes
- **WHEN** all bounding box pairs have IoU ≤ 0.5
- **THEN** no overlap warnings are emitted for that image

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

### Requirement: Per-engine latency reporting
The benchmark report SHALL record per-image latency for each production OCR engine path that runs on that image.

#### Scenario: Successful tri-engine run
- **WHEN** PaddleOCR, MangaOCR, and Vision OCR all complete for an image
- **THEN** the report SHALL include latency entries for each engine on that image

#### Scenario: Engine failure after timing starts
- **WHEN** an engine fails after benchmark timing has started
- **THEN** the report SHALL record the failure and MAY omit latency for that engine if no completed measurement is available

### Requirement: Plain-text report output
The system SHALL write a timestamped plain-text report to `examples/output/report-YYYYMMDD-HHmmss.txt` after processing all images.

#### Scenario: Successful run
- **WHEN** all images have been processed
- **THEN** a report file is created containing: header with timestamp and image count, per-image sections with region results, and a summary section

#### Scenario: Output directory does not exist
- **WHEN** `examples/output/` does not exist at run time
- **THEN** the system SHALL create the directory before writing the report

#### Scenario: Repeated runs
- **WHEN** the benchmark is run multiple times
- **THEN** each run produces a new timestamped file without overwriting previous reports

### Requirement: Report summary section
The report SHALL include a summary at the end listing: total regions detected, number of overlap warnings, number of MangaOCR failures, and number of VisionOCR failures.

#### Scenario: Summary correctness
- **WHEN** the report is generated
- **THEN** the summary counts SHALL match the detailed per-image data in the same report

### Requirement: Independent execution
The benchmark SHALL be runnable via a dedicated Xcode Scheme (`OCRBenchmark`) without triggering the main application test suite.

#### Scenario: Main scheme test run
- **WHEN** the developer runs tests with the main `MangaTranslator` scheme
- **THEN** the OCR benchmark tests SHALL NOT execute

#### Scenario: Benchmark scheme test run
- **WHEN** the developer switches to the `OCRBenchmark` scheme and runs tests
- **THEN** the full benchmark executes and produces a report

### Requirement: Benchmark suite includes targeted regression checks for known PaddleOCR empty cases
The OCR benchmark capability SHALL provide targeted regression validation for known PaddleOCR benchmark crops that previously produced empty or newline-only results in the production Swift runtime.

#### Scenario: Regression case remains covered
- **WHEN** the benchmark-oriented regression suite runs
- **THEN** it includes the known PaddleOCR empty-case crops as explicit validation targets

#### Scenario: Fixed runtime on known empty case
- **WHEN** the production Swift PaddleOCR path is executed on a known benchmark-empty crop after the runtime fix
- **THEN** the regression result records non-empty recognition behavior instead of an empty or newline-only output
