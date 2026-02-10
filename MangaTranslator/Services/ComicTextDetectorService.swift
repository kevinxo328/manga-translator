import Foundation
import AppKit
import OnnxRuntimeBindings

struct DetectedTextRegion {
    let boundingBox: CGRect
    let confidence: Float
    let classIndex: Int // 0 = text, 1 = bubble
}

final class ComicTextDetectorService {
    private static let inputSize = 1024
    private static let confidenceThreshold: Float = 0.4
    private static let nmsThreshold: Float = 0.35

    private var session: ORTSession?

    func detectTextRegions(in image: NSImage) throws -> [DetectedTextRegion] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try detectTextRegions(in: cgImage)
    }

    func detectTextRegions(in cgImage: CGImage) throws -> [DetectedTextRegion] {
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

        return postprocessYolo(
            predictions: predictions,
            numBoxes: numBoxes,
            numOutputs: numOutputs,
            origW: origW,
            origH: origH,
            resizedW: resizedW,
            resizedH: resizedH
        )
    }

    // MARK: - Private

    private func getSession() throws -> ORTSession {
        if let session { return session }

        guard let modelPath = Bundle.main.path(forResource: "comic-text-detector", ofType: "onnx") else {
            throw ComicTextDetectorError.modelNotFound
        }

        let env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setLogSeverityLevel(.warning)
        let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
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
    ) -> [DetectedTextRegion] {
        let wRatio = Float(origW) / Float(resizedW)
        let hRatio = Float(origH) / Float(resizedH)
        let numClasses = numOutputs - 5

        // Parse predictions: [cx, cy, w, h, objectness, class0, class1, ...]
        var allBoxes = [[DetectedTextRegion]](repeating: [], count: numClasses)

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
            if confidence < Self.confidenceThreshold { continue }

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
            allBoxes[bestClassIdx].append(region)
        }

        // Apply NMS per class
        var result = [DetectedTextRegion]()
        for classIdx in 0..<numClasses {
            let nmsResult = nonMaximumSuppression(allBoxes[classIdx], threshold: Self.nmsThreshold)
            result.append(contentsOf: nmsResult)
        }

        return result
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
}

enum ComicTextDetectorError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "comic-text-detector.onnx not found in app bundle"
        }
    }
}
