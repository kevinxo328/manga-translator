import Vision
import AppKit

struct VisionOCRService {
    func recognizeText(in image: NSImage, sourceLanguage: Language = .ja) async throws -> [TextObservation] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try await recognizeText(in: cgImage, sourceLanguage: sourceLanguage)
    }

    func recognizeText(in cgImage: CGImage, sourceLanguage: Language = .ja) async throws -> [TextObservation] {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let observations = results.compactMap { observation -> TextObservation? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }

                    // Filter out low confidence results
                    guard candidate.confidence > 0.15 else { return nil }

                    let box = observation.boundingBox
                    let imageRect = CGRect(
                        x: box.origin.x * imageWidth,
                        y: (1 - box.origin.y - box.height) * imageHeight,
                        width: box.width * imageWidth,
                        height: box.height * imageHeight
                    )

                    return TextObservation(
                        boundingBox: imageRect,
                        text: candidate.string,
                        confidence: candidate.confidence
                    )
                }

                continuation.resume(returning: observations)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = [sourceLanguage.visionLanguageCode]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Failed to create CGImage from input"
        }
    }
}
