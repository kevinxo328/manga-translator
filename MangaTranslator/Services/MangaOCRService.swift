import Foundation
import AppKit
import os

final class MangaOCRService {
    private let detector = ComicTextDetectorService()
    var recognizer: (any OCRRecognizing)?
    private let logger = Logger(subsystem: "MangaTranslator", category: "MangaOCR")

    func resetRecognizer() {
        recognizer = nil
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

        logger.info("Detecting text regions...")
        let regions = try detector.detectTextRegions(in: cgImage)
        logger.info("Found \(regions.count) text regions")

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
                logger.warning("OCR failed for region \(index): \(error.localizedDescription)")
                continue
            }
        }

        logger.info("Recognized \(bubbles.count) text bubbles")
        return bubbles
    }
}
