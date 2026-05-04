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
