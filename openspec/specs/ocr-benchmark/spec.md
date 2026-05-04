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
For each detected text region, the system SHALL run both `MangaOCRService` and `VisionOCRService` and record their outputs side by side.

#### Scenario: Both engines succeed
- **WHEN** both MangaOCR and VisionOCR return a result for a region
- **THEN** the report SHALL show both results on adjacent lines prefixed with `MangaOCR:` and `VisionOCR:`

#### Scenario: One engine fails
- **WHEN** one engine throws an error or returns empty text for a region
- **THEN** the report SHALL show the failure indicator (e.g., `[error]` or `[empty]`) for that engine while still showing the other engine's result

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
