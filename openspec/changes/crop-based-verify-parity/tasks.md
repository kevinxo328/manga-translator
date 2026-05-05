## 1. Swift Detector Export Helper

- [ ] 1.1 Write Swift tests for a detector export helper that takes page image paths and emits JSON text-region boxes from `ComicTextDetectorService`
- [ ] 1.2 Write Swift tests for helper edge cases: missing image path, unreadable image, and page with zero detected regions
- [ ] 1.3 Implement the Swift helper/test entry point and JSON schema used by `verify.py`

## 2. Python Crop-Based Verification

- [ ] 2.1 Write Python tests for parsing detector-export JSON into verification samples
- [ ] 2.2 Write Python tests for crop expansion parity with `PaddleOCRVLRecognizer.expandedCropRegion()` boundary cases
- [ ] 2.3 Write Python tests proving `--test-images` uses detector-derived crops and never sends full pages directly to OCR
- [ ] 2.4 Implement detector-helper invocation inside `verify.py` for `--test-images`
- [ ] 2.5 Replace page-level sample preparation/reporting with region-level crop verification and page summaries derived from region records
- [ ] 2.6 Preserve and verify `--crop-manifest` support for curated crop datasets

## 3. Documentation And Reporting

- [ ] 3.1 Update `scripts/convert_model/README.md` to describe detector-driven crop verification as the default `--test-images` behavior
- [ ] 3.2 Add report/output documentation for zero-region pages and optional detector JSON retention behavior

## 4. End-to-End Validation

- [ ] 4.1 Run Swift tests covering the detector export helper and confirm JSON output is stable
- [ ] 4.2 Run Python unit tests for `scripts/convert_model/tests`
- [ ] 4.3 Run `python verify.py --test-images ../../examples/book1` and confirm the workflow completes with detector-driven crops and region-level output
