import Foundation
import AppKit

actor MangaOCRService {
    private let detector: ComicTextDetecting
    var recognizer: (any OCRRecognizing)?

    init(detector: ComicTextDetecting = ComicTextDetectorService()) {
        self.detector = detector
    }

    func resetRecognizer() {
        recognizer?.unload()
        recognizer = nil
    }

    func setRecognizer(_ recognizer: (any OCRRecognizing)?) {
        self.recognizer = recognizer
    }

    static func makeRecognizer() throws -> any OCRRecognizing {
        let tokenizer = try MangaOCRTokenizer()
        return MangaOCRRecognizer(tokenizer: tokenizer)
    }

    func recognizeAndCluster(in image: NSImage) throws -> [BubbleCluster] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try recognizeAndCluster(in: cgImage)
    }

    func recognizeAndCluster(in cgImage: CGImage) throws -> [BubbleCluster] {
        if recognizer == nil {
            recognizer = try Self.makeRecognizer()
        }
        guard let recognizer else {
            throw MangaOCRError.inferenceError("failed to initialize recognizer")
        }

        DebugLogger.shared.log("Detecting text regions...", level: .info, category: .ocrManga)
        let regions = try detector.detectTextRegions(in: cgImage)
        DebugLogger.shared.log("Found \(regions.count) text regions", level: .info, category: .ocrManga)

        if regions.isEmpty { return [] }

        var bubbles = [BubbleCluster]()
        for (index, region) in regions.enumerated() {
            if region.boundingBox.width < 10 || region.boundingBox.height < 10 {
                continue
            }

            do {
                let (text, confidence) = try recognizer.recognizeText(in: cgImage, region: region.boundingBox)
                if text.isEmpty { continue }

                let observation = TextObservation(
                    boundingBox: region.boundingBox,
                    text: text,
                    confidence: confidence
                )

                let bubble = BubbleCluster(
                    boundingBox: region.boundingBox,
                    text: text,
                    observations: [observation],
                    index: index
                )
                bubbles.append(bubble)
            } catch let error as PaddleOCRError {
                throw error
            } catch {
                DebugLogger.shared.log("OCR failed for region \(index): \(error.localizedDescription)", level: .warning, category: .ocrManga)
                continue
            }
        }

        DebugLogger.shared.log("Recognized \(bubbles.count) text bubbles", level: .info, category: .ocrManga)
        return bubbles
    }
}
