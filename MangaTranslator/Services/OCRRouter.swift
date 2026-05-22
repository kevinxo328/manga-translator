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
    private let inferenceCoordinator: (any ModelInferenceCoordinating)?

    private var usingPaddleOCR = false
    private var cachedPaddleOCR: (any OCRRecognizing)?

    init(
        mangaOCRService: MangaOCRService? = nil,
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: (any ModelDownloadManaging)? = nil,
        paddleOCRFactory: @escaping () throws -> any OCRRecognizing = { throw PaddleOCRError.modelUnavailable },
        paddleOCRCacheCleanup: any PaddleOCRGPUCacheCleaning = NoOpPaddleOCRGPUCacheCleanup(),
        inferenceCoordinator: (any ModelInferenceCoordinating)? = nil
    ) {
        self.mangaOCRService = mangaOCRService ?? MangaOCRService()
        self.capabilityChecker = capabilityChecker
        self.downloadManager = downloadManager ?? ModelDownloadService.shared
        self.paddleOCRFactory = paddleOCRFactory
        self.paddleOCRCacheCleanup = paddleOCRCacheCleanup
        self.inferenceCoordinator = inferenceCoordinator
    }

    #if arch(arm64)
    @MainActor
    static func makeProductionRouter(
        mangaOCRService: MangaOCRService? = nil,
        capabilityChecker: any DeviceCapabilityChecking = DeviceCapabilityService.shared,
        downloadManager: (any ModelDownloadManaging)? = nil,
        inferenceCoordinator: (any ModelInferenceCoordinating)? = nil
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

        let sharedService = ModelDownloadService.shared
        return OCRRouter(
            mangaOCRService: mangaOCRService,
            capabilityChecker: capabilityChecker,
            downloadManager: downloadManager ?? sharedService,
            paddleOCRFactory: {
                guard let modelDir = resolvedModelDirectory else {
                    throw PaddleOCRError.modelUnavailable
                }
                return PaddleOCRVLRecognizer(modelDirectory: modelDir)
            },
            paddleOCRCacheCleanup: MLXPaddleOCRGPUCacheCleanup(),
            inferenceCoordinator: resolveInferenceCoordinator(
                downloadManager: downloadManager,
                inferenceCoordinator: inferenceCoordinator,
                fallback: sharedService
            )
        )
    }
    #endif

    /// Resolves which `ModelInferenceCoordinating` instance the router should
    /// use, in this precedence order:
    ///   1. an explicit `inferenceCoordinator` argument,
    ///   2. the supplied `downloadManager` when it also conforms to
    ///      `ModelInferenceCoordinating` (so routing state and inference
    ///      bookkeeping stay on the same instance),
    ///   3. the supplied `fallback`.
    ///
    /// Exposed as a static helper so the precedence is testable without
    /// running `makeProductionRouter`, which would otherwise pull in the real
    /// `PaddleOCRVLRecognizer` factory.
    static func resolveInferenceCoordinator(
        downloadManager: (any ModelDownloadManaging)?,
        inferenceCoordinator: (any ModelInferenceCoordinating)?,
        fallback: any ModelInferenceCoordinating
    ) -> any ModelInferenceCoordinating {
        if let inferenceCoordinator {
            return inferenceCoordinator
        }
        if let dual = downloadManager as? any ModelInferenceCoordinating {
            return dual
        }
        return fallback
    }

    func processPage(image: NSImage, sourceLanguage: Language) async throws -> MangaOCRPageResult {
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

    func processWithPaddleOCR(image: NSImage) async throws -> MangaOCRPageResult {
        usingPaddleOCR = true
        defer { paddleOCRCacheCleanup.clearGPUCache() }

        // Register the inference window so any lifecycle mutation (e.g.
        // `ModelDownloadService.delete()`) suspends until OCR finishes. The
        // release uses inline `await` rather than `defer { Task { ... } }`
        // so the active count drops before this function returns, matching
        // the lifecycle actor's handoff semantics.
        await inferenceCoordinator?.beginInference()
        do {
            if cachedPaddleOCR == nil {
                cachedPaddleOCR = try paddleOCRFactory()
            }
            await mangaOCRService.setRecognizer(cachedPaddleOCR)
            let result = try await mangaOCRService.recognizeAndCluster(in: image)
            let sorted = readingOrderSorter.sort(result.bubbles)
            DebugLogger.shared.log("Completed OCR with PaddleOCR, bubbles=\(sorted.count)", level: .info, category: .ocrPaddle)
            await inferenceCoordinator?.endInference()
            return MangaOCRPageResult(bubbles: sorted, textPixelMask: result.textPixelMask, lowConfidenceDetectionCount: result.lowConfidenceDetectionCount)
        } catch let error as PaddleOCRError {
            await inferenceCoordinator?.endInference()
            DebugLogger.shared.log("PaddleOCR failed: \(error.localizedDescription)", level: .error, category: .ocrPaddle)
            throw error
        } catch {
            await inferenceCoordinator?.endInference()
            DebugLogger.shared.log("PaddleOCR failed with unexpected error: \(error.localizedDescription)", level: .error, category: .ocrPaddle)
            throw PaddleOCRError.inferenceFailed(error.localizedDescription)
        }
    }

    func processWithMangaOCR(image: NSImage) async throws -> MangaOCRPageResult {
        if usingPaddleOCR {
            await mangaOCRService.resetRecognizer()
            usingPaddleOCR = false
        }
        let result = try await mangaOCRService.recognizeAndCluster(in: image)
        let sorted = readingOrderSorter.sort(result.bubbles)
        DebugLogger.shared.log("Completed OCR with MangaOCR, bubbles=\(sorted.count)", level: .info, category: .ocrManga)
        return MangaOCRPageResult(bubbles: sorted, textPixelMask: result.textPixelMask, lowConfidenceDetectionCount: result.lowConfidenceDetectionCount)
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
