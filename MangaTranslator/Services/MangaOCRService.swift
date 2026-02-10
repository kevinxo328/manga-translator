import Foundation
import AppKit
import os

final class MangaOCRService {
    private let detector = ComicTextDetectorService()
    private var recognizer: MangaOCRRecognizer?
    private let logger = Logger(subsystem: "MangaTranslator", category: "MangaOCR")

    func recognizeAndCluster(in image: NSImage) throws -> [BubbleCluster] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try recognizeAndCluster(in: cgImage)
    }

    func recognizeAndCluster(in cgImage: CGImage) throws -> [BubbleCluster] {
        // Initialize recognizer lazily
        if recognizer == nil {
            let tokenizer = try MangaOCRTokenizer()
            recognizer = MangaOCRRecognizer(tokenizer: tokenizer)
        }
        guard let recognizer else {
            throw MangaOCRError.inferenceError("failed to initialize recognizer")
        }

        // Step 1: Detect text regions
        logger.info("Detecting text regions...")
        let regions = try detector.detectTextRegions(in: cgImage)
        logger.info("Found \(regions.count) text regions")

        if regions.isEmpty { return [] }

        // Step 2: For each detected region, run OCR
        var bubbles = [BubbleCluster]()
        for (index, region) in regions.enumerated() {
            // Skip very small regions (likely noise)
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
            } catch {
                logger.warning("OCR failed for region \(index): \(error.localizedDescription)")
                continue
            }
        }

        logger.info("Recognized \(bubbles.count) text bubbles")
        return bubbles
    }
}
