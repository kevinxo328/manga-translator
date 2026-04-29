import Foundation
import AppKit
import os

final class OCRRouter {
    let mangaOCRService: MangaOCRService
    private let visionOCRService: VisionOCRService
    private let bubbleDetector = BubbleDetector()
    private let readingOrderSorter = ReadingOrderSorter()
    private let capabilityChecker: any DeviceCapabilityChecking
    private let downloadManager: any ModelDownloadManaging
    private let paddleOCRFactory: () throws -> any OCRRecognizing
    private let logger = Logger(subsystem: "MangaTranslator", category: "OCRRouter")

    private var usingPaddleOCR = false

    init(
        mangaOCRService: MangaOCRService = MangaOCRService(),
        visionOCRService: VisionOCRService = VisionOCRService(),
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: any ModelDownloadManaging = ModelDownloadService.shared,
        paddleOCRFactory: @escaping () throws -> any OCRRecognizing = { throw PaddleOCRError.modelUnavailable }
    ) {
        self.mangaOCRService = mangaOCRService
        self.visionOCRService = visionOCRService
        self.capabilityChecker = capabilityChecker
        self.downloadManager = downloadManager
        self.paddleOCRFactory = paddleOCRFactory
    }

    func processPage(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
        if sourceLanguage == .ja {
            let (downloadState, downloadEnabled) = await MainActor.run {
                (downloadManager.state, downloadManager.isPaddleOCREnabled)
            }
            let shouldUsePaddleOCR = capabilityChecker.checkPaddleOCRCapability() != .unsupported
                && downloadState == .downloaded
                && downloadEnabled

            if shouldUsePaddleOCR {
                // Strict mode: surface errors directly; do not fall back to MangaOCR or Vision.
                usingPaddleOCR = true
                do {
                    mangaOCRService.recognizer = try paddleOCRFactory()
                    let bubbles = try mangaOCRService.recognizeAndCluster(in: image)
                    return readingOrderSorter.sort(bubbles)
                } catch let error as PaddleOCRError {
                    throw error
                } catch {
                    throw PaddleOCRError.inferenceFailed(error.localizedDescription)
                }
            }

            // MangaOCR pipeline — reset recognizer when switching from PaddleOCR.
            if usingPaddleOCR {
                mangaOCRService.resetRecognizer()
                usingPaddleOCR = false
            }
            do {
                logger.info("Using manga-ocr pipeline for Japanese")
                let bubbles = try mangaOCRService.recognizeAndCluster(in: image)
                return readingOrderSorter.sort(bubbles)
            } catch {
                logger.warning("Manga-ocr failed, falling back to Vision OCR: \(error.localizedDescription)")
                return try await visionFallback(image: image, sourceLanguage: sourceLanguage)
            }
        } else {
            return try await visionFallback(image: image, sourceLanguage: sourceLanguage)
        }
    }

    func resetPaddleOCRRecognizer() {
        mangaOCRService.resetRecognizer()
        usingPaddleOCR = false
    }

    private func visionFallback(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
        let observations = try await visionOCRService.recognizeText(in: image, sourceLanguage: sourceLanguage)
        let bubbles = bubbleDetector.detectBubbles(from: observations)
        return readingOrderSorter.sort(bubbles)
    }
}
