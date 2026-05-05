import Foundation
import AppKit
import os

#if arch(arm64)
import MangaTranslatorMLX
#endif

@MainActor
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
        mangaOCRService: MangaOCRService? = nil,
        visionOCRService: VisionOCRService? = nil,
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: (any ModelDownloadManaging)? = nil,
        paddleOCRFactory: @escaping () throws -> any OCRRecognizing = { throw PaddleOCRError.modelUnavailable }
    ) {
        self.mangaOCRService = mangaOCRService ?? MangaOCRService()
        self.visionOCRService = visionOCRService ?? VisionOCRService()
        self.capabilityChecker = capabilityChecker
        self.downloadManager = downloadManager ?? ModelDownloadService.shared
        self.paddleOCRFactory = paddleOCRFactory
    }

    #if arch(arm64)
    @MainActor
    static func makeProductionRouter(
        mangaOCRService: MangaOCRService? = nil,
        visionOCRService: VisionOCRService? = nil,
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: (any ModelDownloadManaging)? = nil
    ) -> OCRRouter {
        let resolvedModelDirectory = ModelDownloadService.resolvedProductionModelDirectory()
        if let resolvedModelDirectory {
            Logger(subsystem: "MangaTranslator", category: "OCRRouter").info(
                "Configured production PaddleOCR model directory: \(resolvedModelDirectory.path, privacy: .public)"
            )
        } else {
            Logger(subsystem: "MangaTranslator", category: "OCRRouter").warning(
                "Configured production PaddleOCR model directory is unavailable"
            )
        }

        return OCRRouter(
            mangaOCRService: mangaOCRService,
            visionOCRService: visionOCRService,
            capabilityChecker: capabilityChecker,
            downloadManager: downloadManager,
            paddleOCRFactory: {
                guard let modelDir = resolvedModelDirectory else {
                    throw PaddleOCRError.modelUnavailable
                }
                return PaddleOCRVLRecognizer(modelDirectory: modelDir)
            }
        )
    }
    #endif

    func processPage(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
        if sourceLanguage == .ja {
            let (downloadState, downloadEnabled) = await MainActor.run {
                (downloadManager.state, downloadManager.isPaddleOCREnabled)
            }
            let capability = capabilityChecker.checkPaddleOCRCapability()
            let shouldUsePaddleOCR = capability != .unsupported
                && downloadState == .downloaded
                && downloadEnabled

            logRoutingDecision(
                sourceLanguage: sourceLanguage,
                capability: capability,
                downloadState: downloadState,
                downloadEnabled: downloadEnabled,
                selectedEngine: shouldUsePaddleOCR ? "PaddleOCR" : "MangaOCR"
            )

            if shouldUsePaddleOCR {
                return try processWithPaddleOCR(image: image)
            }

            return try await processWithMangaOCR(image: image, sourceLanguage: sourceLanguage, allowVisionFallback: true)
        } else {
            logger.info(
                "OCR route selected: VisionOCR because sourceLanguage=\(sourceLanguage.rawValue, privacy: .public)"
            )
            return try await processWithVisionOCR(image: image, sourceLanguage: sourceLanguage)
        }
    }

    func resetPaddleOCRRecognizer() {
        mangaOCRService.resetRecognizer()
        usingPaddleOCR = false
    }

    func processWithPaddleOCR(image: NSImage) throws -> [BubbleCluster] {
        usingPaddleOCR = true
        do {
            logger.info("Starting OCR with PaddleOCR")
            mangaOCRService.recognizer = try paddleOCRFactory()
            let bubbles = try mangaOCRService.recognizeAndCluster(in: image)
            logger.info("Completed OCR with PaddleOCR, bubbles=\(bubbles.count, privacy: .public)")
            return readingOrderSorter.sort(bubbles)
        } catch let error as PaddleOCRError {
            logger.error("PaddleOCR failed: \(error.localizedDescription, privacy: .public)")
            throw error
        } catch {
            logger.error("PaddleOCR failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            throw PaddleOCRError.inferenceFailed(error.localizedDescription)
        }
    }

    func processWithMangaOCR(
        image: NSImage,
        sourceLanguage: Language = .ja,
        allowVisionFallback: Bool
    ) async throws -> [BubbleCluster] {
        if usingPaddleOCR {
            mangaOCRService.resetRecognizer()
            usingPaddleOCR = false
        }
        do {
            logger.info("Starting OCR with MangaOCR")
            let bubbles = try mangaOCRService.recognizeAndCluster(in: image)
            logger.info("Completed OCR with MangaOCR, bubbles=\(bubbles.count, privacy: .public)")
            return readingOrderSorter.sort(bubbles)
        } catch {
            guard allowVisionFallback else { throw error }
            logger.warning("MangaOCR failed, falling back to VisionOCR: \(error.localizedDescription, privacy: .public)")
            return try await processWithVisionOCR(image: image, sourceLanguage: sourceLanguage)
        }
    }

    func processWithVisionOCR(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
        logger.info("Starting OCR with VisionOCR for sourceLanguage=\(sourceLanguage.rawValue, privacy: .public)")
        let observations = try await visionOCRService.recognizeText(in: image, sourceLanguage: sourceLanguage)
        let bubbles = bubbleDetector.detectBubbles(from: observations)
        logger.info("Completed OCR with VisionOCR, bubbles=\(bubbles.count, privacy: .public)")
        return readingOrderSorter.sort(bubbles)
    }

    private func logRoutingDecision(
        sourceLanguage: Language,
        capability: PaddleOCRCapability,
        downloadState: ModelDownloadState,
        downloadEnabled: Bool,
        selectedEngine: String
    ) {
        logger.info(
            """
            OCR route selected: \(selectedEngine, privacy: .public) \
            sourceLanguage=\(sourceLanguage.rawValue, privacy: .public) \
            capability=\(capability.logDescription, privacy: .public) \
            downloadState=\(downloadState.logDescription, privacy: .public) \
            downloadEnabled=\(downloadEnabled, privacy: .public)
            """
        )
    }
}

private extension PaddleOCRCapability {
    var logDescription: String {
        switch self {
        case .supported:
            return "supported"
        case .supportedWithWarning(let ram):
            return "supportedWithWarning(ram:\(ram)GB)"
        case .unsupported:
            return "unsupported"
        }
    }
}

private extension ModelDownloadState {
    var logDescription: String {
        switch self {
        case .notDownloaded:
            return "notDownloaded"
        case .downloading(let progress):
            return "downloading(\(Int(progress * 100))%)"
        case .downloaded:
            return "downloaded"
        case .failed(let error):
            return "failed(\(error.code))"
        }
    }
}
