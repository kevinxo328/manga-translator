## Why

PaddleOCR can crash on Apple Silicon while Core Image converts a cropped `CGImage`, producing `EXC_BAD_ACCESS/SIGBUS` in the ImageIO backing store. The current non-blocking OCR boundary passes a UI-owned `NSImage` into a background actor, allowing AppKit/ImageIO image data to be accessed concurrently with SwiftUI rendering; the fix must make image ownership explicit without moving OCR back to the UI-critical context.

## What Changes

- Establish an owned, pixel-backed image handoff before OCR leaves the UI actor.
- Pass only an immutable `CGImage` or equivalent owned pixel buffer across the OCR actor boundary.
- Ensure cropping and `CIImage` creation do not depend on the displayed `NSImage` or lazy ImageIO backing data.
- Preserve PaddleOCR routing, strict error behavior, OCR output, model lifecycle, and UI responsiveness.
- Add regression coverage for image lifetime, concurrent UI/OCR access, large-image memory behavior, and successful Core Image conversion.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `paddleocr-recognizer`: require safe, owned image input across the background inference boundary and guarantee that valid OCR inputs do not crash when the source page is concurrently displayed or evicted.

## Impact

- Affected code: `TranslationViewModel`, `OCRRouter`, `MangaOCRService`, `PaddleOCRVLRecognizer`, and `DefaultPaddleOCREngine`.
- Affected tests: OCR router, PaddleOCR recognizer, and end-to-end OCR integration coverage.
- Runtime trade-off: one owned pixel representation may increase peak memory and incur an image conversion cost, while avoiding unsafe `NSImage` sharing and preserving background OCR execution.
- No new dependencies, user-facing settings, routing changes, or translation/cache behavior changes.
