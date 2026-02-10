import Foundation
import AppKit
import os

final class OCRRouter {
    private let mangaOCRService = MangaOCRService()
    private let visionOCRService = VisionOCRService()
    private let bubbleDetector = BubbleDetector()
    private let readingOrderSorter = ReadingOrderSorter()
    private let logger = Logger(subsystem: "MangaTranslator", category: "OCRRouter")

    func processPage(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
        if sourceLanguage == .ja {
            do {
                logger.info("Using manga-ocr pipeline for Japanese")
                let bubbles = try mangaOCRService.recognizeAndCluster(in: image)
                let sorted = readingOrderSorter.sort(bubbles)
                return sorted
            } catch {
                logger.warning("Manga-ocr failed, falling back to Vision OCR: \(error.localizedDescription)")
                return try await visionFallback(image: image, sourceLanguage: sourceLanguage)
            }
        } else {
            return try await visionFallback(image: image, sourceLanguage: sourceLanguage)
        }
    }

    private func visionFallback(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
        let observations = try await visionOCRService.recognizeText(in: image, sourceLanguage: sourceLanguage)
        let bubbles = bubbleDetector.detectBubbles(from: observations)
        let sorted = readingOrderSorter.sort(bubbles)
        return sorted
    }
}
