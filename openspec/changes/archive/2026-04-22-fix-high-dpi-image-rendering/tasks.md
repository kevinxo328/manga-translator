## 1. Write Failing Tests (TDD — Red Phase)

- [x] 1.1 Create `MangaTranslatorTests/ImageViewerTests.swift` using Swift Testing
- [x] 1.2 Write test: `pixelSize(of:)` returns `(1114, 1600)` for a 600 DPI NSImage created from `001.jpg`-style bitmap rep
- [x] 1.3 Write test: `pixelSize(of:)` returns `(1080, 1535)` for a 72 DPI NSImage (point size equals pixel size)
- [x] 1.4 Write test: `pixelSize(of:)` falls back to `NSImage.size` when no bitmap rep exists
- [x] 1.5 Write test: scale for 600 DPI image (1114×1600 px) in 500×700 pt geometry equals `min(500/1114, 700/1600)` ≈ 0.4375 (no 1.0 cap)
- [x] 1.6 Write test: `scaledRect` maps bubble at pixel (500, 300) on 1114×1600 image displayed in 488×700 pt area to correct display coordinates
- [x] 1.7 Write test: 72 DPI image scale calculation is unchanged (scale < 1.0 as before)
- [x] 1.8 Confirm all new tests fail (Red)

## 2. Implement Production Fix (TDD — Green Phase)

- [x] 2.1 Add `private func pixelSize(of image: NSImage) -> CGSize` to `ImageViewer.swift` — reads `pixelsWide`/`pixelsHigh` from first `NSBitmapImageRep`, falls back to `image.size`
- [x] 2.2 Replace `let originalSize = image?.size ?? CGSize(width: 1, height: 1)` with `pixelSize(of:)` call
- [x] 2.3 Remove the `1.0` cap from the `min(...)` scale calculation
- [x] 2.4 Confirm all tests pass (Green)

## 3. Delta Spec Sync

- [x] 3.1 Run `openspec sync --change fix-high-dpi-image-rendering` to merge delta spec into `openspec/specs/image-viewer/spec.md`

## 4. Verification

- [x] 4.1 Run full test suite — no regressions (pre-existing ModelsTests failure unrelated to this change)
- [x] 4.2 Load `001.jpg` (600 DPI) manually in the app — image fills the viewer
- [x] 4.3 Load a standard 72 DPI manga page — display unchanged
- [x] 4.4 Verify bubble overlays are correctly positioned on the 600 DPI image
