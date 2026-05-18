# OCR Benchmark

## Purpose

The OCR Benchmark capability provides a standalone diagnostic tool that runs both MangaOCR and PaddleOCR engines side by side on a set of sample images and produces a plain-text report. It is intended for development and quality evaluation — not for production use.

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
For each image, the system SHALL invoke two OCR engines as independent production pipelines and record their outputs separately:

- **PaddleOCR path**: process the image through the production Japanese OCR path that uses `PaddleOCRVLRecognizer` for region recognition
- **MangaOCR path**: call `MangaOCRService.recognizeAndCluster(in:)` directly; the service handles detection and per-region recognition internally
After the engines produce their bubble lists, the system SHALL compare them through one greedy IoU matching pass (threshold ≥ 0.5):

- PaddleOCR vs MangaOCR

Bubbles that cannot be paired in a given comparison SHALL be recorded as unmatched for that comparison. The benchmark test SHALL contain no direct image-cropping logic and SHALL NOT invoke the PaddleOCR full-page engine path.

#### Scenario: PaddleOCR and MangaOCR produce overlapping regions
- **WHEN** PaddleOCR and MangaOCR both return bubbles and at least one PaddleOCR bubble has IoU ≥ 0.5 with a MangaOCR bubble
- **THEN** the report SHALL show the paired PaddleOCR/MangaOCR result with both texts and the IoU score

#### Scenario: A comparison has no overlapping regions
- **WHEN** all PaddleOCR bubbles have IoU < 0.5 against every bubble from the compared engine
- **THEN** the report SHALL record all PaddleOCR bubbles and all compared-engine bubbles as unmatched for that comparison

#### Scenario: Full-page engine benchmark is excluded
- **WHEN** the OCR benchmark suite runs
- **THEN** it SHALL NOT call `DefaultPaddleOCREngine.infer(image:)` with a full-page source image as a benchmark path

### Requirement: Unmatched region reporting
The report SHALL include unmatched-region sections for PaddleOCR vs MangaOCR. Unmatched PaddleOCR bubbles and unmatched MangaOCR bubbles SHALL be listed with bounding box and recognised text.

#### Scenario: Unmatched PaddleOCR bubble in PaddleOCR vs MangaOCR
- **WHEN** a PaddleOCR bubble has no corresponding MangaOCR bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it in the unmatched PaddleOCR section for the PaddleOCR/MangaOCR comparison

#### Scenario: Unmatched MangaOCR bubble
- **WHEN** a MangaOCR bubble has no corresponding PaddleOCR bubble with IoU ≥ 0.5
- **THEN** the report SHALL include it in the unmatched MangaOCR section for the PaddleOCR/MangaOCR comparison

#### Scenario: No unmatched bubbles in a comparison
- **WHEN** every bubble in a comparison is paired
- **THEN** the unmatched sections for that comparison SHALL be omitted

### Requirement: Summary counts reflect independent pipelines
The summary section SHALL report:

- total PaddleOCR vs MangaOCR paired regions
- unmatched PaddleOCR regions
- unmatched MangaOCR regions
- per-engine image failure counts for PaddleOCR and MangaOCR

#### Scenario: Summary correctness for PaddleOCR vs MangaOCR
- **WHEN** the report is generated
- **THEN** paired + unmatched PaddleOCR count for the PaddleOCR/MangaOCR comparison SHALL equal total PaddleOCR bubbles considered in that comparison, and paired + unmatched MangaOCR count SHALL equal total MangaOCR bubbles

#### Scenario: Engine failure count
- **WHEN** an engine produces no output for an image
- **THEN** the summary SHALL increment that engine's image failure count without masking successful outputs from the other engines

### Requirement: Per-engine latency reporting
The benchmark report SHALL record per-image latency for each production OCR engine path that runs on that image.

#### Scenario: Successful dual-engine run
- **WHEN** PaddleOCR and MangaOCR both complete for an image
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
The report SHALL include a summary at the end listing: paired/unmatched counts and failure counts for PaddleOCR and MangaOCR.

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

### Requirement: Low-confidence detection counter
For each image, the benchmark report SHALL record the number of detector outputs whose confidence falls in the band `[0.40, 0.60)`. This counter monitors the FP-risk margin around the current shared threshold so that a future corpus-diversification audit can detect drift without requiring a full visual re-audit.

#### Scenario: Page with no marginal detections
- **WHEN** every detection on a page has confidence at or above `0.60`
- **THEN** the report records `lowConfidenceDetections = 0` for that page

#### Scenario: Page with marginal detections
- **WHEN** a page produces detections at confidences `[0.95, 0.91, 0.45, 0.52]`
- **THEN** the report records `lowConfidenceDetections = 2` for that page

### Requirement: Inverted-bubble counter
For each image, the benchmark report SHALL record the number of `BubbleCluster` results whose `isInverted` flag is `true`. This counter validates that polarity detection (see `bubble-detection` spec) is firing on pages known to contain inverted bubbles.

#### Scenario: Page with only normal-polarity bubbles
- **WHEN** every detected bubble on a page has `isInverted == false`
- **THEN** the report records `invertedBubbles = 0` for that page

#### Scenario: Page with several inverted-polarity bubbles
- **WHEN** a page contains a mix of normal and inverted bubbles, and 3 of them are classified as inverted
- **THEN** the report records `invertedBubbles = 3` for that page
