import Vision
import AppKit

struct VisionOCRService {
    var usesLanguageCorrection: Bool = true
    var recognitionLanguages: [String] = ["ja-JP", "en-US"]
    // Default Vision threshold (3.125%) filters out furigana and sound effects in manga
    var minimumTextHeightFraction: Float = 0.01

    func recognitionLanguages(for language: Language) -> [Locale.Language] {
        var langs: [Locale.Language] = [Locale.Language(identifier: language.visionLanguageCode)]
        let english = Locale.Language(identifier: "en-US")
        if !langs.contains(english) {
            langs.append(english)
        }
        return langs
    }

    func recognizeText(in image: NSImage, sourceLanguage: Language = .ja) async throws -> [TextObservation] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try await recognizeText(in: cgImage, sourceLanguage: sourceLanguage)
    }

    func recognizeText(in cgImage: CGImage, sourceLanguage: Language = .ja) async throws -> [TextObservation] {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        request.minimumTextHeightFraction = minimumTextHeightFraction
        request.recognitionLanguages = recognitionLanguages(for: sourceLanguage)

        let results = try await request.perform(on: cgImage)

        return results.compactMap { observation -> TextObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard candidate.confidence > 0.15 else { return nil }

            let box = observation.boundingBox
            // NormalizedRect uses lower-left origin; convert to upper-left for AppKit
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
