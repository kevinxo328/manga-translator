import Testing
import AppKit
@testable import MangaTranslator

@Suite("ImageViewer pixel size and scale calculations")
struct ImageViewerTests {

    // Creates an NSImage with explicit pixel and DPI metadata, simulating high-DPI scans
    private func makeImage(pixelsWide: Int, pixelsHigh: Int, dpi: Double) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        // Set point size to match DPI (pixels * 72 / dpi)
        rep.size = CGSize(
            width: Double(pixelsWide) * 72.0 / dpi,
            height: Double(pixelsHigh) * 72.0 / dpi
        )
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - pixelSize(of:)

    @Test("pixelSize returns actual pixel dimensions for 600 DPI image")
    func pixelSizeFor600DPI() {
        let image = makeImage(pixelsWide: 1114, pixelsHigh: 1600, dpi: 600)
        // NSImage.size would be ~(133.68, 192) due to DPI scaling
        #expect(image.size.width < 200) // confirm point size is small
        let size = imagePixelSize(of: image)
        #expect(size.width == 1114)
        #expect(size.height == 1600)
    }

    @Test("pixelSize returns pixel dimensions for 72 DPI image")
    func pixelSizeFor72DPI() {
        let image = makeImage(pixelsWide: 1080, pixelsHigh: 1535, dpi: 72)
        // At 72 DPI, point size equals pixel dimensions
        #expect(image.size.width == 1080)
        let size = imagePixelSize(of: image)
        #expect(size.width == 1080)
        #expect(size.height == 1535)
    }

    @Test("pixelSize falls back to NSImage.size when no bitmap rep exists")
    func pixelSizeFallbackToImageSize() {
        let image = NSImage(size: CGSize(width: 100, height: 200))
        // No NSBitmapImageRep added — fallback to image.size
        let size = imagePixelSize(of: image)
        #expect(size.width == 100)
        #expect(size.height == 200)
    }

    // MARK: - Scale calculation (no 1.0 cap)

    @Test("scale for 600 DPI image fills available space without 1.0 cap")
    func scaleFor600DPIImageFillsViewer() {
        let image = makeImage(pixelsWide: 1114, pixelsHigh: 1600, dpi: 600)
        let pixSize = imagePixelSize(of: image)
        let geomSize = CGSize(width: 500, height: 700)

        // Scale without cap: should be ≈ 0.4375
        let scale = min(geomSize.width / pixSize.width, geomSize.height / pixSize.height)
        let expected = min(500.0 / 1114.0, 700.0 / 1600.0)
        #expect(abs(scale - expected) < 0.001)
        #expect(scale < 1.0) // naturally < 1.0, no cap needed

        // Confirm the old NSImage.size-based scale would exceed 1.0 (and be broken)
        let pointSize = image.size
        let brokenScale = min(geomSize.width / pointSize.width, geomSize.height / pointSize.height)
        #expect(brokenScale > 1.0) // proves old code would cap and show tiny image
    }

    // MARK: - scaledBubbleRect

    @Test("scaledBubbleRect maps pixel bubble coordinates to display coordinates")
    func scaledBubbleRectMapping() {
        // 1114×1600 px image displayed in 488×700 pt area
        let pixelSize = CGSize(width: 1114, height: 1600)
        let displaySize = CGSize(width: 488, height: 700)
        let bubble = CGRect(x: 500, y: 300, width: 100, height: 80)

        let result = scaledBubbleRect(bubble, imagePixelSize: pixelSize, displaySize: displaySize, offset: .zero)

        let expectedX = 500.0 * (488.0 / 1114.0)  // ≈ 219.0
        let expectedY = 300.0 * (700.0 / 1600.0)  // ≈ 131.25
        let expectedW = 100.0 * (488.0 / 1114.0)  // ≈ 43.8
        let expectedH = 80.0 * (700.0 / 1600.0)   // ≈ 35.0

        #expect(abs(result.origin.x - expectedX) < 0.01)
        #expect(abs(result.origin.y - expectedY) < 0.01)
        #expect(abs(result.width - expectedW) < 0.01)
        #expect(abs(result.height - expectedH) < 0.01)
    }

    @Test("scaledBubbleRect applies non-zero offset correctly")
    func scaledBubbleRectWithOffset() {
        let pixelSize = CGSize(width: 1000, height: 1000)
        let displaySize = CGSize(width: 500, height: 500)
        let bubble = CGRect(x: 100, y: 200, width: 50, height: 50)
        let offset = CGPoint(x: 10, y: 20)

        let result = scaledBubbleRect(bubble, imagePixelSize: pixelSize, displaySize: displaySize, offset: offset)

        #expect(abs(result.origin.x - (100.0 * 0.5 + 10)) < 0.01)
        #expect(abs(result.origin.y - (200.0 * 0.5 + 20)) < 0.01)
    }

    // MARK: - 72 DPI unchanged

    @Test("scale for 72 DPI image is the same as before the fix")
    func scaleFor72DPIImageUnchanged() {
        let image = makeImage(pixelsWide: 1080, pixelsHigh: 1535, dpi: 72)
        let pixSize = imagePixelSize(of: image)
        let geomSize = CGSize(width: 500, height: 600)

        let scale = min(geomSize.width / pixSize.width, geomSize.height / pixSize.height)
        let expected = min(500.0 / 1080.0, 600.0 / 1535.0)

        #expect(abs(scale - expected) < 0.001)
        #expect(scale < 1.0)
    }
}
