## Context

`ImageViewer` computes display size using `NSImage.size`, which returns a CGSize in **AppKit points** calculated as `pixels × (72 / imageDPI)`. At 72 DPI this equals pixel dimensions; at higher DPI values it is smaller. A 600 DPI scan of 1114×1600 px yields `NSImage.size` ≈ (133, 192) points, so `scale = min(geomW/133, geomH/192, 1.0)` hits the 1.0 cap and the image displays at 133×192 points.

Both OCR pipelines (Vision and ComicTextDetector) derive bounding boxes from `cgImage.width / cgImage.height`, which are **actual pixel dimensions**. Using `NSImage.size` as the coordinate reference in `scaledRect` creates a mismatch: overlays appear in the wrong positions whenever DPI ≠ 72.

## Goals / Non-Goals

**Goals:**
- Display every image at the largest size that fits in the available area (zoom-to-fit).
- Correctly position bubble overlays regardless of image DPI metadata.
- Cover the fix with unit tests (TDD) before touching production code.

**Non-Goals:**
- Zoom controls (manual in/out, 1:1, fit-width) — out of scope.
- Changing how images are loaded (`NSImage(contentsOf:)`) — the loading path is unchanged.
- Supporting image formats that produce non-`NSBitmapImageRep` representations (all tested formats produce bitmap reps).

## Decisions

### Decision 1: Read pixel dimensions from `NSBitmapImageRep`

**Chosen:** In `ImageViewer`, replace `image?.size` with a helper that reads `pixelsWide` / `pixelsHigh` from the first `NSBitmapImageRep` in `image.representations`, falling back to `image.size` for non-bitmap reps.

**Alternatives considered:**
- `NSImage.cgImage(forProposedRect:).width/height` — works, but creates a CGImage allocation on every layout pass.
- Storing pixel dimensions on `MangaPage` at load time — avoids repeated rep lookups but spreads the fix across two files with no benefit at this scale.

### Decision 2: Remove the `1.0` scale cap

**Chosen:** Remove `, 1.0` from the `min(...)` call so images always scale to fill the available space.

**Rationale:** The cap was intended to prevent upscaling, but manga pages are always at least as large as the viewer in practice. Keeping the cap would still break 600 DPI images even after the pixel-dimension fix (point size < viewer → scale > 1 → still capped).

### Decision 3: TDD — write tests before production changes

**Chosen:** Write `ImageViewerTests.swift` covering the pixel extraction logic and `scaledRect` behavior, then implement to make them pass.

**Rationale:** The scale calculation is pure arithmetic with clear expected values; unit tests are straightforward and catch regressions in both dimensions.

## Risks / Trade-offs

- **Non-bitmap reps (PDF, vector):** `NSBitmapImageRep` lookup returns nil → falls back to `NSImage.size`. These are not supported input formats so this is acceptable.
- **Removing the 1.0 cap:** Tiny images (e.g., 50×50 px) will now upscale and may look pixelated. Manga pages are never this small, so the risk is theoretical.

## Migration Plan

1. Add `ImageViewerTests.swift` with failing tests.
2. Extract a `pixelSize(of:)` helper (pure function, testable) in `ImageViewer.swift`.
3. Swap `originalSize` to use `pixelSize(of:)` and remove the `1.0` cap.
4. Verify all tests pass; run app manually with a 600 DPI image.

No data migration needed. No rollback strategy required (single-file UI change).
