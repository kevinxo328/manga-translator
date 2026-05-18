import CoreGraphics
import Foundation

private let luminanceThreshold: Float = 128
private let minNonTextPixels = 16

func classifyInverted(canvas: CGImage, seg: CGImage, region: CGRect) -> Bool {
    let centerX = region.midX
    let centerY = region.midY
    let patchHalf: CGFloat = 32.0
    let sampleRect = CGRect(
        x: centerX - patchHalf, y: centerY - patchHalf,
        width: 64, height: 64
    ).integral.intersection(
        CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    )
    guard sampleRect.width > 0 && sampleRect.height > 0 else { return false }

    guard let canvasCrop = canvas.cropping(to: sampleRect),
          let segCrop = seg.cropping(to: sampleRect) else { return false }

    let w = canvasCrop.width
    let h = canvasCrop.height

    guard let canvasPixels = readRGBA(cgImage: canvasCrop, width: w, height: h),
          let segPixels = readGray(cgImage: segCrop, width: w, height: h) else { return false }

    var totalLuminance: Float = 0
    var nonTextCount = 0

    for i in 0..<(w * h) {
        guard segPixels[i] == 0 else { continue }  // skip text pixels
        let r = Float(canvasPixels[i * 4])
        let g = Float(canvasPixels[i * 4 + 1])
        let b = Float(canvasPixels[i * 4 + 2])
        totalLuminance += 0.299 * r + 0.587 * g + 0.114 * b
        nonTextCount += 1
    }

    guard nonTextCount >= minNonTextPixels else {
        DebugLogger.shared.log(
            "classifyInverted: only \(nonTextCount) non-text pixels in region \(region); defaulting to false",
            level: .warning, category: .ocrManga
        )
        return false
    }

    return (totalLuminance / Float(nonTextCount)) < luminanceThreshold
}

private func readRGBA(cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

private func readGray(cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: width * height)
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}
