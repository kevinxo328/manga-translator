import Foundation
import AppKit
import OnnxRuntimeBindings

public struct DetectedTextRegion {
    public let boundingBox: CGRect
    public let confidence: Float
    public let classIndex: Int // 0 = text, 1 = bubble

    public init(boundingBox: CGRect, confidence: Float, classIndex: Int) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.classIndex = classIndex
    }
}

public protocol ComicTextRegionDetecting {
    func detectTextRegions(in image: NSImage) throws -> [DetectedTextRegion]
}

struct ComicTextDetectorExportRegion: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Float
    let classIndex: Int
}

struct ComicTextDetectorExportPage: Codable, Equatable {
    let imagePath: String
    let pageWidth: Int
    let pageHeight: Int
    let regions: [ComicTextDetectorExportRegion]
}

struct ComicTextDetectorExportDocument: Codable, Equatable {
    let schemaVersion: Int
    let pages: [ComicTextDetectorExportPage]
}

enum ComicTextDetectorExportError: LocalizedError, Equatable {
    case imageNotFound(String)
    case unreadableImage(String)

    var errorDescription: String? {
        switch self {
        case .imageNotFound(let path):
            return "image not found: \(path)"
        case .unreadableImage(let path):
            return "image is unreadable: \(path)"
        }
    }
}

public struct ComicTextDetectorExporter {
    let detector: any ComicTextRegionDetecting

    public init(detector: any ComicTextRegionDetecting) {
        self.detector = detector
    }

    func export(pageImagePaths: [String]) throws -> ComicTextDetectorExportDocument {
        let pages = try pageImagePaths.map(exportPage)
        return ComicTextDetectorExportDocument(schemaVersion: 1, pages: pages)
    }

    func writeJSON(document: ComicTextDetectorExportDocument, to outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: outputURL)
    }

    public func writeJSON(pageImagePaths: [String], to outputURL: URL) throws {
        try writeJSON(document: export(pageImagePaths: pageImagePaths), to: outputURL)
    }

    private func exportPage(from imagePath: String) throws -> ComicTextDetectorExportPage {
        let imageURL = URL(fileURLWithPath: imagePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw ComicTextDetectorExportError.imageNotFound(imageURL.path)
        }
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ComicTextDetectorExportError.unreadableImage(imageURL.path)
        }

        let regions = try detector.detectTextRegions(in: image).map { region in
            let box = region.boundingBox.standardized
            return ComicTextDetectorExportRegion(
                x: Double(box.origin.x),
                y: Double(box.origin.y),
                width: Double(box.width),
                height: Double(box.height),
                confidence: region.confidence,
                classIndex: region.classIndex
            )
        }

        return ComicTextDetectorExportPage(
            imagePath: imageURL.path,
            pageWidth: cgImage.width,
            pageHeight: cgImage.height,
            regions: regions
        )
    }
}

struct ComicTextDetectorResult {
    let regions: [DetectedTextRegion]
    let textPixelMask: CGImage?
    let lowConfidenceRegionCount: Int
}

protocol ComicTextDetecting: Sendable {
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult
}

extension ComicTextDetectorService: ComicTextDetecting, @unchecked Sendable {}

public class ComicTextDetectorService: ComicTextRegionDetecting {
    private static let inputSize = 1024
    private static let confidenceThreshold: Float = 0.60
    private static let nmsThreshold: Float = 0.35

    private var session: ORTSession?
    private let modelURLProvider: () -> URL?

    public init(modelURLProvider: @escaping () -> URL? = {
        Bundle.main.url(forResource: "comic-text-detector", withExtension: "onnx")
    }) {
        self.modelURLProvider = modelURLProvider
    }

    public func detectTextRegions(in image: NSImage) throws -> [DetectedTextRegion] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try detectTextRegions(in: cgImage).regions
    }

    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        let session = try getSession()

        let origW = cgImage.width
        let origH = cgImage.height
        let inputSize = Self.inputSize

        // Compute resize dimensions maintaining aspect ratio
        let (resizedW, resizedH): (Int, Int)
        if origW >= origH {
            resizedW = inputSize
            resizedH = inputSize * origH / origW
        } else {
            resizedW = inputSize * origW / origH
            resizedH = inputSize
        }

        // Preprocess: resize, pad, normalize to (1, 3, 1024, 1024)
        let inputData = try preprocessImage(cgImage, resizedW: resizedW, resizedH: resizedH, inputSize: inputSize)

        // Create input tensor
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)]
        let inputTensor = try ORTValue(tensorData: NSMutableData(data: inputData),
                                       elementType: .float,
                                       shape: shape)

        // Run inference
        let outputs = try session.run(withInputs: ["images": inputTensor],
                                      outputNames: ["blk", "seg", "det"],
                                      runOptions: nil)

        guard let blkTensor = outputs["blk"] else {
            throw OCRError.invalidImage
        }

        // Parse YOLOv5 predictions
        let blkData = try blkTensor.tensorData() as Data
        let blkShape = try blkTensor.tensorTypeAndShapeInfo().shape
        let numBoxes = blkShape[1].intValue
        let numOutputs = blkShape[2].intValue

        let predictions = blkData.withUnsafeBytes { ptr -> [Float] in
            Array(ptr.bindMemory(to: Float.self))
        }

        let (regions, lowConfCount) = postprocessYolo(
            predictions: predictions,
            numBoxes: numBoxes,
            numOutputs: numOutputs,
            origW: origW,
            origH: origH,
            resizedW: resizedW,
            resizedH: resizedH
        )

        // Build seg mask only when detections exist
        let segMask: CGImage?
        if regions.isEmpty {
            segMask = nil
        } else if let segTensor = outputs["seg"] {
            segMask = buildSegMask(from: segTensor, origW: origW, origH: origH, resizedW: resizedW, resizedH: resizedH)
        } else {
            segMask = nil
        }

        return ComicTextDetectorResult(
            regions: regions,
            textPixelMask: segMask,
            lowConfidenceRegionCount: lowConfCount
        )
    }

    // MARK: - Private

    private func getSession() throws -> ORTSession {
        if let session { return session }

        guard let modelURL = modelURLProvider() else {
            throw ComicTextDetectorError.modelNotFound
        }

        let env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setLogSeverityLevel(.warning)
        let session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)
        self.session = session
        return session
    }

    private func preprocessImage(_ cgImage: CGImage, resizedW: Int, resizedH: Int, inputSize: Int) throws -> Data {
        // Draw image into a bitmap context to get raw pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // Draw at resized dimensions
        guard let context = CGContext(data: nil,
                                      width: resizedW,
                                      height: resizedH,
                                      bitsPerComponent: 8,
                                      bytesPerRow: resizedW * bytesPerPixel,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else {
            throw OCRError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: resizedW, height: resizedH))

        guard let pixelData = context.data else {
            throw OCRError.invalidImage
        }

        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: resizedW * resizedH * bytesPerPixel)

        // Create float array in NCHW format (1, 3, inputSize, inputSize), padded with zeros
        var floatData = [Float](repeating: 0, count: 3 * inputSize * inputSize)
        let channelStride = inputSize * inputSize

        for y in 0..<resizedH {
            for x in 0..<resizedW {
                let pixelIndex = (y * resizedW + x) * bytesPerPixel
                let r = Float(pixels[pixelIndex]) / 255.0
                let g = Float(pixels[pixelIndex + 1]) / 255.0
                let b = Float(pixels[pixelIndex + 2]) / 255.0

                let spatialIndex = y * inputSize + x
                floatData[0 * channelStride + spatialIndex] = r
                floatData[1 * channelStride + spatialIndex] = g
                floatData[2 * channelStride + spatialIndex] = b
            }
        }

        return Data(bytes: &floatData, count: floatData.count * MemoryLayout<Float>.size)
    }

    private func postprocessYolo(
        predictions: [Float],
        numBoxes: Int,
        numOutputs: Int,
        origW: Int,
        origH: Int,
        resizedW: Int,
        resizedH: Int
    ) -> ([DetectedTextRegion], Int) {
        let wRatio = Float(origW) / Float(resizedW)
        let hRatio = Float(origH) / Float(resizedH)
        let numClasses = numOutputs - 5

        // Boxes that survive the main threshold and boxes in the low-confidence band are
        // collected separately so each set can go through its own NMS pass. The
        // low-confidence metric is counted from raw predictions before NMS so it tracks
        // detector drift even when overlapping anchors collapse to a single region.
        let lowConfBandMin: Float = 0.40
        let lowConfBandMax: Float = 0.60

        var allBoxes = [[DetectedTextRegion]](repeating: [], count: numClasses)
        var allLowConfBoxes = [[DetectedTextRegion]](repeating: [], count: numClasses)

        for i in 0..<numBoxes {
            let offset = i * numOutputs
            let objectness = predictions[offset + 4]

            // Find best class
            var bestClassIdx = 0
            var bestClassScore: Float = 0
            for c in 0..<numClasses {
                let score = predictions[offset + 5 + c]
                if score > bestClassScore {
                    bestClassScore = score
                    bestClassIdx = c
                }
            }

            let confidence = objectness * bestClassScore

            let cx = predictions[offset]
            let cy = predictions[offset + 1]
            let w = predictions[offset + 2]
            let h = predictions[offset + 3]

            let xmin = max(0, (cx - w / 2) * wRatio)
            let xmax = min(Float(origW), (cx + w / 2) * wRatio)
            let ymin = max(0, (cy - h / 2) * hRatio)
            let ymax = min(Float(origH), (cy + h / 2) * hRatio)

            let region = DetectedTextRegion(
                boundingBox: CGRect(x: CGFloat(xmin), y: CGFloat(ymin),
                                    width: CGFloat(xmax - xmin), height: CGFloat(ymax - ymin)),
                confidence: confidence,
                classIndex: bestClassIdx
            )

            if confidence >= Self.confidenceThreshold {
                allBoxes[bestClassIdx].append(region)
            } else if confidence >= lowConfBandMin && confidence < lowConfBandMax {
                allLowConfBoxes[bestClassIdx].append(region)
            }
        }

        // Apply NMS per class for kept detections
        var result = [DetectedTextRegion]()
        for classIdx in 0..<numClasses {
            result.append(contentsOf: nonMaximumSuppression(allBoxes[classIdx], threshold: Self.nmsThreshold))
        }

        // Apply NMS to low-conf band separately; count raw predictions in the band.
        var lowConfidenceCount = 0
        for classIdx in 0..<numClasses {
            lowConfidenceCount += allLowConfBoxes[classIdx].count
        }

        return (result, lowConfidenceCount)
    }

    private func buildSegMask(from segTensor: ORTValue, origW: Int, origH: Int, resizedW: Int, resizedH: Int) -> CGImage? {
        guard let segData = try? segTensor.tensorData() as Data,
              let segShape = try? segTensor.tensorTypeAndShapeInfo().shape,
              segShape.count == 4 else { return nil }
        let maskH = segShape[2].intValue
        let maskW = segShape[3].intValue
        let floats = segData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard floats.count == maskH * maskW else { return nil }

        // Threshold at 0.5 → binary uint8
        var binaryPixels = [UInt8](repeating: 0, count: maskH * maskW)
        for i in 0..<(maskH * maskW) {
            binaryPixels[i] = floats[i] >= 0.5 ? 255 : 0
        }

        // Dilate by 3px to ensure text pixels are fully masked
        binaryPixels = dilateGray(pixels: binaryPixels, width: maskW, height: maskH, radius: 3)

        // Crop the valid resizedW × resizedH region from the top-left of the 1024×1024 mask.
        // Preprocessing letterboxes the image into the top-left corner; the remainder is zero-padded.
        // Stretching the full mask to origW×origH would shift coordinates on non-square pages.
        let cropW = min(resizedW, maskW)
        let cropH = min(resizedH, maskH)
        var croppedPixels = [UInt8](repeating: 0, count: cropW * cropH)
        for y in 0..<cropH {
            for x in 0..<cropW {
                croppedPixels[y * cropW + x] = binaryPixels[y * maskW + x]
            }
        }

        let graySpace = CGColorSpaceCreateDeviceGray()
        let maskCropped = croppedPixels.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: cropW,
                height: cropH,
                bitsPerComponent: 8,
                bytesPerRow: cropW,
                space: graySpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
        guard let maskCropped else { return nil }

        // Scale the cropped valid region to original image resolution
        guard let resizeCtx = CGContext(
            data: nil,
            width: origW,
            height: origH,
            bitsPerComponent: 8,
            bytesPerRow: origW,
            space: graySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        resizeCtx.interpolationQuality = .none
        resizeCtx.draw(maskCropped, in: CGRect(x: 0, y: 0, width: origW, height: origH))
        return resizeCtx.makeImage()
    }

    private func dilateGray(pixels: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard pixels[y * width + x] != 0 else { continue }
                let yMin = max(0, y - radius)
                let yMax = min(height - 1, y + radius)
                let xMin = max(0, x - radius)
                let xMax = min(width - 1, x + radius)
                for ny in yMin...yMax {
                    for nx in xMin...xMax {
                        output[ny * width + nx] = 255
                    }
                }
            }
        }
        return output
    }

    private func nonMaximumSuppression(_ boxes: [DetectedTextRegion], threshold: Float) -> [DetectedTextRegion] {
        let sorted = boxes.sorted { $0.confidence > $1.confidence }
        var keep = [DetectedTextRegion]()

        for box in sorted {
            var shouldKeep = true
            for kept in keep {
                let iou = computeIoU(box.boundingBox, kept.boundingBox)
                if iou > threshold {
                    shouldKeep = false
                    break
                }
            }
            if shouldKeep {
                keep.append(box)
            }
        }

        return keep
    }

    private func computeIoU(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        let intersectionArea = Float(intersection.width * intersection.height)
        let unionArea = Float(a.width * a.height + b.width * b.height) - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    // Exposed for testing only
    func testPostprocessYolo(predictions: [Float], numBoxes: Int, numOutputs: Int, origW: Int, origH: Int, resizedW: Int, resizedH: Int) -> ([DetectedTextRegion], Int) {
        postprocessYolo(predictions: predictions, numBoxes: numBoxes, numOutputs: numOutputs, origW: origW, origH: origH, resizedW: resizedW, resizedH: resizedH)
    }
}

enum ComicTextDetectorError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "comic-text-detector.onnx not found in app bundle"
        }
    }
}
