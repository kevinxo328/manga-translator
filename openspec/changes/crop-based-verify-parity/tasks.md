## 1. Swift Detector Export Helper

- [x] 1.1 Write Swift tests for a detector export helper that takes page image paths and emits JSON text-region boxes from `ComicTextDetectorService`
- [x] 1.2 Write Swift tests for helper edge cases: missing image path, unreadable image, and page with zero detected regions
- [x] 1.3 Implement the Swift helper/test entry point and JSON schema used by `verify.py`

## 2. Python Crop-Based Verification

- [x] 2.1 Write Python tests for parsing detector-export JSON into verification samples
- [x] 2.2 Write Python tests for crop expansion parity with `PaddleOCRVLRecognizer.expandedCropRegion()` boundary cases
- [x] 2.3 Write Python tests proving `--test-images` uses detector-derived crops and never sends full pages directly to OCR
- [x] 2.4 Implement detector-helper invocation inside `verify.py` for `--test-images`
- [x] 2.5 Replace page-level sample preparation/reporting with region-level crop verification and page summaries derived from region records
- [x] 2.6 Preserve and verify `--crop-manifest` support for curated crop datasets

## 3. Documentation And Reporting

- [x] 3.1 Update `scripts/convert_model/README.md` to describe detector-driven crop verification as the default `--test-images` behavior
- [x] 3.2 Add report/output documentation for zero-region pages and optional detector JSON retention behavior

## 4. End-to-End Validation

- [x] 4.1 Run Swift tests covering the detector export helper and confirm JSON output is stable
- [x] 4.2 Run Python unit tests for `scripts/convert_model/tests`
- [x] 4.3 Run `python verify.py --test-images ../../examples/book1` and confirm the workflow completes with detector-driven crops and region-level output
