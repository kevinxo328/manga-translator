import Testing
import CoreGraphics
@testable import MangaTranslator

@Suite("BubblePolarityClassifier")
struct BubblePolarityClassifierTests {

    private func makeSolidCGImage(width: Int, height: Int, grayValue: UInt8) -> CGImage? {
        var pixels = [UInt8](repeating: grayValue, count: width * height)
        return pixels.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }

    private func makeRGBImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = r
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = b
            pixels[i * 4 + 3] = 255
        }
        return pixels.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }

    // Task 3.1: white-on-dark canvas → isInverted = true
    @Test("Dark background with white text patch classifies as inverted")
    func darkBackgroundIsInverted() throws {
        // Dark canvas (value 10 ≈ nearly black)
        let canvas = try #require(makeRGBImage(width: 1024, height: 1024, r: 10, g: 10, b: 10))
        // seg mask all zeros (no text pixels masked)
        let seg = try #require(makeSolidCGImage(width: 1024, height: 1024, grayValue: 0))
        let region = CGRect(x: 400, y: 400, width: 224, height: 224)
        #expect(classifyInverted(canvas: canvas, seg: seg, region: region) == true)
    }

    // Task 3.2: dark-on-white canvas → isInverted = false
    @Test("White background with dark text patch classifies as normal")
    func whiteBackgroundIsNotInverted() throws {
        let canvas = try #require(makeRGBImage(width: 1024, height: 1024, r: 250, g: 250, b: 250))
        let seg = try #require(makeSolidCGImage(width: 1024, height: 1024, grayValue: 0))
        let region = CGRect(x: 400, y: 400, width: 224, height: 224)
        #expect(classifyInverted(canvas: canvas, seg: seg, region: region) == false)
    }

    // Task 3.3: entirely-text interior → returns false with warning
    @Test("All-text interior defaults to false")
    func allTextInteriorDefaultsFalse() throws {
        let canvas = try #require(makeRGBImage(width: 1024, height: 1024, r: 10, g: 10, b: 10))
        // seg mask all 255 (all text pixels)
        let seg = try #require(makeSolidCGImage(width: 1024, height: 1024, grayValue: 255))
        let region = CGRect(x: 400, y: 400, width: 224, height: 224)
        #expect(classifyInverted(canvas: canvas, seg: seg, region: region) == false)
    }
}
