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
        let route = currentRoute()

        logRoutingDecision(
            sourceLanguage: sourceLanguage,
            capability: route.capability,
            downloadState: route.downloadState,
            downloadEnabled: route.downloadEnabled,
            selectedEngine: route.usesPaddleOCR ? "PaddleOCR" : "MangaOCR"
        )

        if route.usesPaddleOCR {
            return try await processWithPaddleOCR(image: image)
        }

        return try await processWithMangaOCR(image: image)
    }

    func processWithPaddleOCR(image: NSImage) async throws -> MangaOCRPageResult {
        try await withPaddleOCRInference(operationDescription: "PaddleOCR") {
            let result = try await mangaOCRService.recognizeAndCluster(in: image)
            let sorted = readingOrderSorter.sort(result.bubbles)
            DebugLogger.shared.log("Completed OCR with PaddleOCR, bubbles=\(sorted.count)", level: .info, category: .ocrPaddle)
            return MangaOCRPageResult(bubbles: sorted, textPixelMask: result.textPixelMask, lowConfidenceDetectionCount: result.lowConfidenceDetectionCount)
        }
    }

    /// Runs `body` inside a PaddleOCR inference window: marks the router as
    /// using PaddleOCR, lazily creates and installs the cached recognizer,
    /// and pairs `beginInference`/`endInference` across the success and both
    /// failure paths. Errors are logged with `operationDescription` as the
    /// message prefix and non-PaddleOCR errors are wrapped in
    /// `PaddleOCRError.inferenceFailed`.
    ///
    /// The inference window suspends any lifecycle mutation (e.g.
    /// `ModelDownloadService.delete()`) until OCR finishes. The release uses
    /// inline `await` rather than `defer { Task { ... } }` so the active
    /// count drops before this function returns, matching the lifecycle
    /// actor's handoff semantics.
    private func withPaddleOCRInference<T>(
        operationDescription: String,
        _ body: @MainActor () async throws -> T
    ) async throws -> T {
        usingPaddleOCR = true
        defer { paddleOCRCacheCleanup.clearGPUCache() }

        await inferenceCoordinator?.beginInference()
        do {
            if cachedPaddleOCR == nil {
                cachedPaddleOCR = try paddleOCRFactory()
            }
            await mangaOCRService.setRecognizer(cachedPaddleOCR)
            let result = try await body()
            await inferenceCoordinator?.endInference()
            return result
        } catch let error as PaddleOCRError {
            await inferenceCoordinator?.endInference()
            DebugLogger.shared.log("\(operationDescription) failed: \(error.localizedDescription)", level: .error, category: .ocrPaddle)
            throw error
        } catch {
            await inferenceCoordinator?.endInference()
            DebugLogger.shared.log("\(operationDescription) failed with unexpected error: \(error.localizedDescription)", level: .error, category: .ocrPaddle)
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

    private struct OCRRoute {
        let capability: PaddleOCRCapability
        let downloadState: ModelDownloadState
        let downloadEnabled: Bool

        var usesPaddleOCR: Bool {
            capability != .unsupported
                && downloadState == .downloaded
                && downloadEnabled
        }
    }

    private func currentRoute() -> OCRRoute {
        OCRRoute(
            capability: capabilityChecker.checkPaddleOCRCapability(),
            downloadState: downloadManager.state,
            downloadEnabled: downloadManager.isPaddleOCREnabled
        )
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

// Abstraction the Edit Mode commit pipeline uses to OCR newly drawn or
// geometry-changed bubble regions. Decouples `TranslationViewModel` from
// `OCRRouter` so tests can substitute a fake. `OCRRouter` conforms below;
// production uses that conformance with whichever recognizer the page's
// initial translation already loaded (PaddleOCR or MangaOCR).
@MainActor
protocol EditModeOCRPerforming {
    func recognizeRegions(
        image: NSImage,
        bubbles: [BubbleCluster],
        sourceLanguage: Language
    ) async throws -> [UUID: String]
}

extension OCRRouter: EditModeOCRPerforming {
    // Per-region OCR for the Edit Mode commit pipeline. Reuses the recognizer
    // that was loaded by the page's initial `processPage` call — the gating
    // rule (`Edit` button enabled only on `.translated`) guarantees one such
    // call has already run, so the recognizer is in cache.
    //
    // No reading-order sort is performed here: the caller already maintains
    // the user's chosen order in `EditSession.workingBubbles`. The result
    // map is keyed by `BubbleCluster.id` so the caller can merge text back
    // by identity.
    func recognizeRegions(
        image: NSImage,
        bubbles: [BubbleCluster],
        sourceLanguage: Language
    ) async throws -> [UUID: String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        let route = currentRoute()
        logRoutingDecision(
            sourceLanguage: sourceLanguage,
            capability: route.capability,
            downloadState: route.downloadState,
            downloadEnabled: route.downloadEnabled,
            selectedEngine: route.usesPaddleOCR ? "PaddleOCR-region" : "MangaOCR-region"
        )

        if route.usesPaddleOCR {
            return try await withPaddleOCRInference(operationDescription: "PaddleOCR region OCR") {
                try await recognizeRegionsWithCurrentRecognizer(cgImage: cgImage, bubbles: bubbles)
            }
        }

        if usingPaddleOCR {
            await mangaOCRService.resetRecognizer()
            usingPaddleOCR = false
        }
        return try await recognizeRegionsWithCurrentRecognizer(cgImage: cgImage, bubbles: bubbles)
    }

    private func recognizeRegionsWithCurrentRecognizer(
        cgImage: CGImage,
        bubbles: [BubbleCluster]
    ) async throws -> [UUID: String] {
        var results: [UUID: String] = [:]
        for bubble in bubbles {
            let text = try await mangaOCRService.recognizeRegion(
                in: cgImage,
                region: bubble.boundingBox
            )
            results[bubble.id] = text
        }
        return results
    }
}

private extension PaddleOCRCapability {
    var logDescription: String {
        switch self {
        case .supported:
            return "supported"
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
