## Why

`ImageViewer` derives display dimensions from `NSImage.size`, which reports size in **points** (pixels × 72 / DPI). High-DPI images (e.g., 600 DPI scans exported by Photoshop) receive a point size far smaller than their pixel dimensions, causing the image to render at a fraction of the available space and making bubble overlays misaligned. The fix is to use actual pixel dimensions from `NSBitmapImageRep` for all scale calculations.

## What Changes

- `ImageViewer` reads pixel dimensions from `NSBitmapImageRep` instead of `NSImage.size` for scale and overlay calculations.
- The `1.0` scale cap is removed so images always scale to fill the available space (zoom-to-fit).
- Unit tests added to cover pixel-based scale calculation and overlay rect mapping for images with various DPI values.

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `image-viewer`: Add requirement that image display MUST use pixel dimensions (not point dimensions) for scale and bubble overlay calculations, and MUST scale to fill the available view area regardless of DPI metadata.

## Impact

- `MangaTranslator/Views/ImageViewer.swift` — change `originalSize` source and remove `1.0` cap
- `MangaTranslatorTests/` — new unit tests for scale calculation logic
