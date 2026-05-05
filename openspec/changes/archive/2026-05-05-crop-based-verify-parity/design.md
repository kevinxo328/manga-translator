## Context

`scripts/convert_model/verify.py` currently supports a page-level path that sends full manga pages directly into PaddleOCR-VL. That does not match the app's high-accuracy OCR pipeline, which first runs `ComicTextDetectorService`, then crops each detected text region with `PaddleOCRVLRecognizer` padding rules before inference. As a result, page-level parity mixes detector mismatch, reading-order noise, and long-generation failure modes into a tool that is supposed to answer a narrower question: whether the quantized model behaves like the BF16 source on the same crops the app actually recognizes.

The app-side detector already exists in Swift and is the source of truth for production behavior. Re-implementing that detector in Python would create another interpretation of resize, padding, NMS, and coordinate restoration, reducing the value of verification.

## Goals / Non-Goals

**Goals:**
- Make `verify.py --test-images ...` evaluate detector-derived crops instead of full pages
- Reuse the app's `ComicTextDetectorService` as the region source of truth
- Reuse `PaddleOCRVLRecognizer` crop expansion semantics when preparing crops for BF16/quantized comparison
- Keep the external developer entry point unchanged while improving parity fidelity
- Preserve optional manifest-based workflows for curated or regression-specific crop sets

**Non-Goals:**
- Replacing or retraining `ComicTextDetectorService`
- Changing app-side OCR routing or user-visible OCR behavior
- Benchmarking bubble clustering quality
- Keeping full-page OCR verification as a supported mode

## Decisions

### D1: `--test-images` becomes detector-driven crop verification

`verify.py` SHALL stop treating page images as direct OCR inputs. When `--test-images` is provided, the script SHALL first obtain detected text regions for each page, then verify parity on per-region crops only.

**Why**: This aligns the verification target with the app's production OCR contract instead of a synthetic whole-page workload.

**Alternative considered**: Keep both page mode and crop mode. Rejected because the page path adds noise, duplicates maintenance, and is explicitly not needed for this change.

### D2: Swift helper test exports detector regions for Python consumption

The detector source of truth SHALL remain in Swift. `verify.py` SHALL invoke a Swift helper/test entry point that runs `ComicTextDetectorService` on the requested pages and emits a JSON payload describing detected regions.

**Why**: The app already contains the exact preprocessing, ONNX invocation, postprocessing, and coordinate restoration logic used in production. Reusing it avoids Python drift.

**Alternative considered**: Port the detector to Python. Rejected because it would create a second implementation to keep in sync and would weaken parity confidence.

### D3: Detector JSON is an internal interchange artifact, not a manual prerequisite

The JSON region list is an implementation detail used to bridge Swift detection and Python verification. `verify.py` SHALL create and consume it automatically for `--test-images`, while optionally allowing developers to keep the file for debugging.

**Why**: The user-facing command should stay simple, but reproducibility and debugging still benefit from a structured detector output artifact.

**Alternative considered**: Require developers to run a separate export step before verification. Rejected because it adds friction without improving the default workflow.

### D4: Crop preparation mirrors `PaddleOCRVLRecognizer.expandedCropRegion()`

Python crop preparation SHALL implement the same expansion policy used in `PaddleOCRVLRecognizer`, including base padding ratio, minimum horizontal/vertical padding, elongated-region horizontal boost, tall-region vertical boost, and final clamping to image bounds.

**Why**: Matching detector boxes alone is insufficient; the OCR model also depends on the app's crop expansion heuristics.

**Alternative considered**: Keep the current generic `crop_padding` flag as the primary mechanism. Rejected because it does not represent the app's runtime behavior closely enough.

### D5: Region-level records become the primary reporting unit

Verification records, pass/fail accounting, and CER analysis SHALL be region-based. Reports MAY still include per-page summaries derived from those region records, but not page-level OCR outputs.

**Why**: Region-level reporting makes regressions actionable and lets developers distinguish OCR drift from detector coverage issues.

**Alternative considered**: Collapse all regions from a page into one combined record. Rejected because it hides which crops regress.

## Risks / Trade-offs

- **Swift helper invocation adds build/test overhead** → Keep the helper narrowly scoped to detector export and invoke only once per verification run, not once per crop
- **Swift detector JSON schema drift could break Python parsing** → Define a small, versioned JSON structure with required fields and test it from both sides
- **Python crop logic could diverge from Swift expansion rules over time** → Add unit tests that assert parity against representative region fixtures and document the shared constants
- **Pages with zero detected regions may hide OCR opportunities** → Report zero-region pages explicitly so detector misses remain visible during verification

## Migration Plan

1. Add a Swift helper/test entry point that accepts page image paths and writes detected regions as JSON.
2. Update `verify.py` to call that helper automatically when `--test-images` is used.
3. Replace page-image sample preparation with detector-region crop preparation.
4. Update Python tests and README examples to reflect detector-driven verification.
5. Run Swift helper tests plus Python verification tests before implementation is considered complete.

Rollback is straightforward: restore the previous `verify.py` page path and stop invoking the Swift helper.

## Open Questions

- Should the detector JSON be deleted by default after a successful run, or retained under a `--keep-detector-json` flag only?
- Should zero-region pages count as hard failures or as observable warnings in the parity summary?
