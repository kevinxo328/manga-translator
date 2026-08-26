## 1. Add failing regression coverage

- [x] 1.1 Add deterministic RGBA8 `NSImage` fixtures and test support for tracking page-snapshot creation in `OCRRouterTests` and the OCR service tests.
- [x] 1.2 Add a failing page-pipeline test that verifies a valid `NSImage` is materialized on the main actor and that the background OCR service receives only the resulting `CGImage`.
- [x] 1.3 Add a failing lifetime test that releases the source `NSImage` before worker processing and verifies repeated `CIImage(cgImage:)` conversion from the owned pixels succeeds.
- [x] 1.4 Add a failing concurrent-access stress test that repeatedly reads the displayed source image while OCR processes the owned snapshot, covering both PaddleOCR and standard MangaOCR routing without a crash or unsafe source-image access.
- [x] 1.5 Add a failing multi-region and 4K-or-larger test that verifies one full-page snapshot is reused for all regions and that materialization failure returns a descriptive error before background inference.

## 2. Implement the owned image handoff

- [x] 2.1 Implement a main-actor image materialization helper that produces a predictable RGBA8/sRGB pixel-backed `CGImage` with an owned data provider and reports invalid-image failures without passing through the source `NSImage`.
- [x] 2.2 Update `OCRRouter.processPage` and the PaddleOCR page path to create one owned snapshot before the actor hop, retain it for the complete page attempt, and preserve routing, strict errors, and page-boundary cleanup behavior.
- [x] 2.3 Update edit-mode region OCR to use the same owned snapshot boundary before calling background recognition, so displayed or evicted `NSImage` state never crosses into OCR execution.
- [x] 2.4 Remove the production `NSImage` conversion from `MangaOCRService` and make the actor-facing page API consume `CGImage` only; update all callers and tests, and audit the detector's legacy `NSImage` overload for remaining production use.
- [x] 2.5 Keep region clamping, cropping, `CIImage` creation, detector coordinates, model lifecycle, and PaddleOCR decode behavior unchanged while verifying they now receive the owned page image.

## 3. Verify behavior and resource trade-offs

- [x] 3.1 Run the focused OCR router, MangaOCR, PaddleOCR recognizer, and end-to-end tests, including strict PaddleOCR failure, invalid-image, boundary-region, blank-image, and model-reload coverage.
- [x] 3.2 Run the complete `MangaTranslator` macOS test scheme and confirm existing UI-responsiveness, routing, cache, and output-parity tests remain green.
- [x] 3.3 Run the PaddleOCR parity diagnostic suite with the approved artifacts and the production-style OCR benchmark when their required inputs are available; confirm recognized text remains identical on the approved regression samples.
- [x] 3.4 Measure main-actor snapshot duration and peak memory for representative 4K-or-larger pages, confirm at most one full-page owned buffer per in-flight page, and record any user-visible responsiveness regression.
- [x] 3.5 Audit production call sites and the final stack with source search to confirm no background OCR actor evaluates `NSImage.cgImage(forProposedRect:context:hints:)` and all Core Image conversions use owned `CGImage` input.
