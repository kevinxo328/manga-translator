import Foundation
import AppKit

#if arch(arm64)
import MangaTranslatorMLX
#endif

@MainActor
final class OCRRouter {
    let mangaOCRService: MangaOCRService
    private let readingOrderSorter = ReadingOrderSorter()
    private let capabilityChecker: any DeviceCapabilityChecking
    private let downloadManager: any ModelDownloadManaging
    private let paddleOCRFactory: () throws -> any OCRRecognizing
    private let paddleOCRCacheCleanup: any PaddleOCRGPUCacheCleaning

    private var usingPaddleOCR = false
    private var cachedPaddleOCR: (any OCRRecognizing)?

    init(
        mangaOCRService: MangaOCRService? = nil,
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: (any ModelDownloadManaging)? = nil,
        paddleOCRFactory: @escaping () throws -> any OCRRecognizing = { throw PaddleOCRError.modelUnavailable },
        paddleOCRCacheCleanup: any PaddleOCRGPUCacheCleaning = NoOpPaddleOCRGPUCacheCleanup()
    ) {
        self.mangaOCRService = mangaOCRService ?? MangaOCRService()
        self.capabilityChecker = capabilityChecker
        self.downloadManager = downloadManager ?? ModelDownloadService.shared
        self.paddleOCRFactory = paddleOCRFactory
        self.paddleOCRCacheCleanup = paddleOCRCacheCleanup
    }

    #if arch(arm64)
    @MainActor
    static func makeProductionRouter(
        mangaOCRService: MangaOCRService? = nil,
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: (any ModelDownloadManaging)? = nil
    ) -> OCRRouter {
        let resolvedModelDirectory = ModelDownloadService.resolvedProductionModelDirectory()
        if let resolvedModelDirectory {
            DebugLogger.shared.log(
                "Configured production PaddleOCR model directory: \(resolvedModelDirectory.path)",
                level: .info, category: .ocrRouter
            )
        } else {
            DebugLogger.shared.log(
                "Configured production PaddleOCR model directory is unavailable",
                level: .warning, category: .ocrRouter
            )
        }

        return OCRRouter(
            mangaOCRService: mangaOCRService,
            capabilityChecker: capabilityChecker,
            downloadManager: downloadManager,
            paddleOCRFactory: {
                guard let modelDir = resolvedModelDirectory else {
                    throw PaddleOCRError.modelUnavailable
                }
                return PaddleOCRVLRecognizer(modelDirectory: modelDir)
            },
            paddleOCRCacheCleanup: MLXPaddleOCRGPUCacheCleanup()
        )
    }
    #endif

    func processPage(image: NSImage, sourceLanguage: Language) async throws -> [BubbleCluster] {
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
            return try await processWithPaddleOCR(image: image)
        }

        return try await processWithMangaOCR(image: image)
    }

    func resetPaddleOCRRecognizer() async {
        await mangaOCRService.resetRecognizer()
        usingPaddleOCR = false
    }

    func processWithPaddleOCR(image: NSImage) async throws -> [BubbleCluster] {
        usingPaddleOCR = true
        defer { paddleOCRCacheCleanup.clearGPUCache() }
        do {
            if cachedPaddleOCR == nil {
                cachedPaddleOCR = try paddleOCRFactory()
            }
            await mangaOCRService.setRecognizer(cachedPaddleOCR)
            let bubbles = try await mangaOCRService.recognizeAndCluster(in: image)
            DebugLogger.shared.log("Completed OCR with PaddleOCR, bubbles=\(bubbles.count)", level: .info, category: .ocrPaddle)
            return readingOrderSorter.sort(bubbles)
        } catch let error as PaddleOCRError {
            DebugLogger.shared.log("PaddleOCR failed: \(error.localizedDescription)", level: .error, category: .ocrPaddle)
            throw error
        } catch {
            DebugLogger.shared.log("PaddleOCR failed with unexpected error: \(error.localizedDescription)", level: .error, category: .ocrPaddle)
            throw PaddleOCRError.inferenceFailed(error.localizedDescription)
        }
    }

    func processWithMangaOCR(image: NSImage) async throws -> [BubbleCluster] {
        if usingPaddleOCR {
            await mangaOCRService.resetRecognizer()
            usingPaddleOCR = false
        }
        let bubbles = try await mangaOCRService.recognizeAndCluster(in: image)
        DebugLogger.shared.log("Completed OCR with MangaOCR, bubbles=\(bubbles.count)", level: .info, category: .ocrManga)
        return readingOrderSorter.sort(bubbles)
    }

    private func logRoutingDecision(
        sourceLanguage: Language,
        capability: PaddleOCRCapability,
        downloadState: ModelDownloadState,
        downloadEnabled: Bool,
        selectedEngine: String
    ) {
        DebugLogger.shared.log(
            "OCR route selected: \(selectedEngine) sourceLanguage=\(sourceLanguage.rawValue) capability=\(capability.logDescription) downloadState=\(downloadState.logDescription) downloadEnabled=\(downloadEnabled)",
            level: .info, category: .ocrRouter
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
