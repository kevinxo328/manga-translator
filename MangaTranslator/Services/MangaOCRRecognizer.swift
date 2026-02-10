import Foundation
import AppKit
import OnnxRuntimeBindings

final class MangaOCRRecognizer {
    private static let imageSize = 224
    private static let imageMean: [Float] = [0.5, 0.5, 0.5]
    private static let imageStd: [Float] = [0.5, 0.5, 0.5]
    private static let maxLength = 300
    private static let decoderStartTokenId: Int64 = 2  // [CLS]
    private static let eosTokenId: Int64 = 3            // [SEP]
    private static let padTokenId: Int64 = 0            // [PAD]

    private var encoderSession: ORTSession?
    private var decoderSession: ORTSession?
    private let tokenizer: MangaOCRTokenizer

    init(tokenizer: MangaOCRTokenizer) {
        self.tokenizer = tokenizer
    }

    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        // Crop the region from the image
        guard let cropped = cgImage.cropping(to: region) else {
            return ("", 0)
        }
        return try recognizeText(in: cropped)
    }

    func recognizeText(in cgImage: CGImage) throws -> (text: String, confidence: Float) {
        let (encoder, decoder) = try getSessions()

        // Preprocess: grayscale -> RGB, resize to 224x224, normalize
        let inputData = try preprocessImage(cgImage)

        let shape: [NSNumber] = [1, 3, NSNumber(value: Self.imageSize), NSNumber(value: Self.imageSize)]
        let pixelValues = try ORTValue(tensorData: NSMutableData(data: inputData),
                                       elementType: .float,
                                       shape: shape)

        // Run encoder
        let encoderOutputs = try encoder.run(withInputs: ["pixel_values": pixelValues],
                                              outputNames: ["last_hidden_state"],
                                              runOptions: nil)

        guard let encoderHiddenStates = encoderOutputs["last_hidden_state"] else {
            throw MangaOCRError.inferenceError("encoder returned no output")
        }

        // Autoregressive decoding (greedy)
        var tokenIds: [Int64] = [Self.decoderStartTokenId]
        var totalLogProb: Float = 0
        var tokenCount = 0

        for _ in 0..<Self.maxLength {
            let inputIdsData = Data(bytes: tokenIds, count: tokenIds.count * MemoryLayout<Int64>.size)
            let inputIdsTensor = try ORTValue(tensorData: NSMutableData(data: inputIdsData),
                                              elementType: .int64,
                                              shape: [1, NSNumber(value: tokenIds.count)])

            let decoderOutputs = try decoder.run(
                withInputs: [
                    "input_ids": inputIdsTensor,
                    "encoder_hidden_states": encoderHiddenStates
                ],
                outputNames: ["logits"],
                runOptions: nil
            )

            guard let logitsTensor = decoderOutputs["logits"] else {
                throw MangaOCRError.inferenceError("decoder returned no logits")
            }

            // Get logits for the last token position
            let logitsData = try logitsTensor.tensorData() as Data
            let vocabSize = 6144
            let seqLen = tokenIds.count
            let lastTokenOffset = (seqLen - 1) * vocabSize

            let logits = logitsData.withUnsafeBytes { ptr -> [Float] in
                let floats = ptr.bindMemory(to: Float.self)
                return Array(floats[lastTokenOffset..<lastTokenOffset + vocabSize])
            }

            // Greedy: argmax
            var maxIdx = 0
            var maxVal: Float = -Float.infinity
            for (i, val) in logits.enumerated() {
                if val > maxVal {
                    maxVal = val
                    maxIdx = i
                }
            }

            // Compute softmax probability for confidence
            let maxLogit = maxVal
            var sumExp: Float = 0
            for val in logits { sumExp += exp(val - maxLogit) }
            let prob = 1.0 / sumExp  // exp(maxLogit - maxLogit) / sumExp
            totalLogProb += log(prob)
            tokenCount += 1

            let nextToken = Int64(maxIdx)
            if nextToken == Self.eosTokenId { break }

            tokenIds.append(nextToken)
        }

        let text = tokenizer.decode(tokenIds.map { Int($0) })
        let avgConfidence = tokenCount > 0 ? exp(totalLogProb / Float(tokenCount)) : 0
        return (text, avgConfidence)
    }

    // MARK: - Private

    private func getSessions() throws -> (ORTSession, ORTSession) {
        if let encoder = encoderSession, let decoder = decoderSession {
            return (encoder, decoder)
        }

        guard let encoderPath = Bundle.main.path(forResource: "encoder_model", ofType: "onnx") else {
            throw MangaOCRError.modelNotFound("encoder_model.onnx")
        }
        guard let decoderPath = Bundle.main.path(forResource: "decoder_model", ofType: "onnx") else {
            throw MangaOCRError.modelNotFound("decoder_model.onnx")
        }

        let env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setLogSeverityLevel(.warning)

        let encoder = try ORTSession(env: env, modelPath: encoderPath, sessionOptions: opts)
        let decoder = try ORTSession(env: env, modelPath: decoderPath, sessionOptions: opts)

        self.encoderSession = encoder
        self.decoderSession = decoder

        return (encoder, decoder)
    }

    private func preprocessImage(_ cgImage: CGImage) throws -> Data {
        let size = Self.imageSize
        let bytesPerPixel = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(data: nil,
                                      width: size,
                                      height: size,
                                      bitsPerComponent: 8,
                                      bytesPerRow: size * bytesPerPixel,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else {
            throw OCRError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let pixelData = context.data else {
            throw OCRError.invalidImage
        }

        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: size * size * bytesPerPixel)

        // Convert to grayscale then back to RGB (matching manga-ocr training pipeline)
        // Then normalize: (pixel / 255.0 - mean) / std
        var floatData = [Float](repeating: 0, count: 3 * size * size)
        let channelStride = size * size

        for y in 0..<size {
            for x in 0..<size {
                let pixelIndex = (y * size + x) * bytesPerPixel
                let r = Float(pixels[pixelIndex])
                let g = Float(pixels[pixelIndex + 1])
                let b = Float(pixels[pixelIndex + 2])

                // Convert to grayscale (ITU-R BT.601)
                let gray = 0.299 * r + 0.587 * g + 0.114 * b

                // Normalize: (gray / 255.0 - 0.5) / 0.5 = gray / 127.5 - 1.0
                let normalized = gray / 127.5 - 1.0

                let spatialIndex = y * size + x
                floatData[0 * channelStride + spatialIndex] = normalized
                floatData[1 * channelStride + spatialIndex] = normalized
                floatData[2 * channelStride + spatialIndex] = normalized
            }
        }

        return Data(bytes: &floatData, count: floatData.count * MemoryLayout<Float>.size)
    }
}
