## Context

`TranslationViewModel` and `OCRRouter` are `@MainActor`-isolated, while `MangaOCRService` is an actor used to move OCR work off the UI-critical context. The current page pipeline passes an `NSImage` from the main actor into `MangaOCRService`, where `NSImage.cgImage(forProposedRect:context:hints:)` is evaluated on the worker actor. The same `NSImage` can also be read by SwiftUI while the page is displayed.

In the reported 1.5.6 crash, Core Image fails inside `CIImage(cgImage:)` while copying from an ImageIO-backed `CGImage`, producing `EXC_BAD_ACCESS/SIGBUS`. The existing recognizer already operates on `CGImage` regions, so the smallest safe boundary is to materialize a stable page image before crossing into the OCR actor.

## Goals / Non-Goals

**Goals:**

- Prevent AppKit `NSImage` instances and lazy ImageIO backing data from crossing the OCR actor boundary.
- Preserve background OCR execution and main-actor responsiveness.
- Preserve detector coordinates, PaddleOCR/MangaOCR routing, strict PaddleOCR errors, OCR output, cache behavior, and model lifecycle.
- Materialize one owned pixel representation per page and reuse it for detection and all region crops.
- Add regression coverage for image handoff, image lifetime, large images, and concurrent page display/OCR access.

**Non-Goals:**

- No change to PaddleOCR model weights, preprocessing math, prompts, decode policy, or translation behavior.
- No fallback from PaddleOCR to MangaOCR.
- No new image-processing dependency or user-facing memory/performance setting.
- No redesign of page image-window eviction beyond ensuring OCR owns its snapshot for the duration of a page attempt.

## Decisions

### 1. Materialize the image on the main actor before the OCR hop

`OCRRouter` will convert the incoming `NSImage` to an owned, pixel-backed `CGImage` while still on the main actor. The existing OCR service and recognizer APIs will receive `CGImage` only; the actor overload that accepts `NSImage` will be removed or made unavailable to production callers.

This keeps all AppKit access at the existing UI boundary and makes the worker input immutable and independent of the displayed `NSImage`. The snapshot will use a predictable RGBA8 bitmap representation and an owned data provider/context image rather than relying on a lazy ImageIO provider.

Alternatives considered:

- Passing `NSImage` into the actor is rejected because it permits concurrent AppKit/ImageIO access with SwiftUI and caused the reported failure mode.
- Passing the image URL and decoding again on the actor avoids sharing `NSImage`, but adds I/O, duplicate decoding, security-scoped-resource handling, and possible differences from the displayed representation.
- Protecting `NSImage` with a lock avoids one explicit race but cannot cover SwiftUI/AppKit's internal reads and could block the UI while OCR is waiting.

### 2. Copy once per page, not once per region

The owned page `CGImage` will be created once at the OCR entry point and passed through detection, polarity classification, cropping, and recognition. Region crops may continue to reference the owned page image because the page snapshot remains retained for the complete actor call.

This bounds the new copy cost to one full-page bitmap per in-flight page rather than multiplying the cost by the number of bubbles. The page snapshot remains a local value and is released when the page OCR attempt completes.

### 3. Keep Core Image and MLX off the UI-critical path

Only the AppKit-to-owned-bitmap conversion occurs on the main actor. Detector inference, crop processing, `CIImage` creation from the owned `CGImage`, and MLX generation remain in `MangaOCRService`/`MangaTranslatorMLX` on the background actor.

This retains the non-blocking design introduced for PaddleOCR. The conversion boundary will be measured in tests or diagnostics so a large-image decode does not silently move the full OCR workload back to the main actor.

### 4. Test the ownership boundary rather than the crash address

Regression tests will assert that the OCR path accepts a stable `CGImage` after the source `NSImage` is no longer needed, that the page service no longer performs `NSImage` conversion on the actor, and that large images do not create per-region copies. A focused integration/stress test will exercise page display access while OCR processes the owned snapshot.

Existing output-parity, routing, strict-error, and UI-responsiveness tests remain the behavioral gates. A crash cannot be made deterministic by asserting only that a mock recognizer was called; the new tests must cross the same `NSImage` → owned bitmap → actor boundary used by production.

## Risks / Trade-offs

- **[Risk]** The RGBA8 snapshot adds approximately `width × height × 4` bytes per in-flight page. → **Mitigation:** copy once per page, do not retain it in `MangaPage`, release it at the page boundary, and retain existing batch/page concurrency limits.
- **[Risk]** Image materialization on the main actor can cause a short decode/copy pause for very large pages. → **Mitigation:** keep the operation limited to one conversion, measure it, and consider background URL decoding only as a separate optimization if measurements show a user-visible stall.
- **[Risk]** A shallow `CGImage` snapshot could still retain lazy ImageIO data. → **Mitigation:** construct the handoff from an owned bitmap buffer/data provider and add a lifetime regression test that drops the source `NSImage` before worker processing.
- **[Risk]** A changed bitmap color format could alter OCR parity. → **Mitigation:** use the existing expected RGBA/sRGB input convention and run the approved PaddleOCR parity suite plus representative detector crops.
- **[Risk]** Changing the service signature can affect tests and benchmark callers. → **Mitigation:** update all callers at the boundary while keeping the internal recognizer protocol's `CGImage` contract unchanged.

## Migration Plan

1. Add the owned-image conversion seam and regression tests before changing the production caller.
2. Change `OCRRouter`/`MangaOCRService` to pass only the owned `CGImage` into the actor.
3. Keep `PaddleOCRVLRecognizer` and `DefaultPaddleOCREngine` behavior unchanged except for receiving stable image data.
4. Run OCR router, recognizer, E2E, and approved PaddleOCR parity tests, including a large-image case.
5. If regressions appear, revert the boundary change as one unit; no persisted data, model files, cache keys, or user settings require migration.

## Open Questions

- Should the owned bitmap helper live in `MangaOCRService` or in a shared image-boundary utility used by both page OCR and edit-mode region OCR?
- Does the current test environment provide a reliable way to stress SwiftUI rendering and OCR simultaneously, or should the regression test use a deterministic repeated `NSImage` read/write stress harness?
- Should the final implementation expose a named owned-image type, or is a private conversion helper returning `CGImage` sufficient without adding an abstraction used only once?
