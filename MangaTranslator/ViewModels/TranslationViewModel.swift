import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

#if arch(arm64)
import MangaTranslatorMLX
#endif

protocol PipelineLogging: Sendable {
    var sessionID: String { get }
    func log(
        _ message: String,
        level: DebugLogLevel,
        category: DebugLogCategory,
        kind: DebugLogKind,
        metadata: [String: String],
        filePath: String?,
        source: String
    )
}

extension PipelineLogging {
    func log(
        _ message: String,
        level: DebugLogLevel,
        category: DebugLogCategory,
        kind: DebugLogKind = .operational,
        metadata: [String: String] = [:],
        filePath: String? = nil,
        source: String = #fileID
    ) {
        log(message, level: level, category: category, kind: kind, metadata: metadata, filePath: filePath, source: source)
    }
}

extension DebugLogger: PipelineLogging {}

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var pages: [MangaPage] = []
    @Published var currentPageIndex: Int = 0
    @Published var highlightedBubbleId: UUID? = nil
    @Published var isProcessing = false
    @Published var errorMessage: String? = nil
    @Published var showMissingKeyAlert = false
    @Published var preferences: PreferencesService
    @Published var activeGlossaryID: String? = nil
    @Published var glossaries: [Glossary] = []
    @Published var sourcePath: String? = nil
    @Published var showFileImporter = false

    var allowedTypes: [UTType] {
        [.image, .folder, .zip, UTType(filenameExtension: "cbz") ?? .zip]
    }

    #if arch(arm64)
    var ocrRouter: OCRRouter
    #else
    var ocrRouter: OCRRouter
    #endif
    private let cacheService = CacheService()
    private let keychainService = KeychainService()
    private var cancellables = Set<AnyCancellable>()
    private let translationServiceOverride: (any TranslationService)?
    private let pipelineLogger: any PipelineLogging

    private var glossaryService: GlossaryService { cacheService.glossaryService }
    var glossaryServiceForView: GlossaryService { cacheService.glossaryService }
    private var recentPageTranslations: [String] = []

    init(
        preferences: PreferencesService,
        ocrRouter: OCRRouter? = nil,
        translationService: (any TranslationService)? = nil,
        pipelineLogger: any PipelineLogging = DebugLogger.shared
    ) {
        self.preferences = preferences
        self.translationServiceOverride = translationService
        self.pipelineLogger = pipelineLogger
        #if arch(arm64)
        self.ocrRouter = ocrRouter ?? OCRRouter.makeProductionRouter()
        #else
        self.ocrRouter = ocrRouter ?? OCRRouter()
        #endif
        glossaries = cacheService.glossaryService.listGlossaries()
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func loadGlossaries() {
        glossaries = glossaryService.listGlossaries()
    }

    var activeGlossary: Glossary? {
        guard let id = activeGlossaryID else { return nil }
        return glossaries.first { $0.id == id }
    }

    // Engine boundary: only OpenAI-compatible and GitHub Copilot consume recent-page summaries.
    // DeepL and Google receive glossary terms but never recent-page context.
    private func usesRecentPageContext(_ engine: TranslationEngine) -> Bool {
        switch engine {
        case .openAI, .githubCopilot: return true
        case .deepL, .google: return false
        }
    }

    private func buildTranslationContext(usesRecentContext: Bool) -> TranslationContext {
        let terms: [GlossaryTerm]
        if let id = activeGlossaryID {
            terms = glossaryService.listTerms(glossaryID: id)
        } else {
            terms = []
        }
        let summaries = usesRecentContext ? recentPageTranslations : []
        return TranslationContext(glossaryTerms: terms, recentPageSummaries: summaries)
    }

    private func appendToRecentContextIfNeeded(_ translated: [TranslatedBubble], usesRecentContext: Bool) {
        guard usesRecentContext else { return }
        let summary = translated
            .sorted { $0.index < $1.index }
            .map { $0.translatedText }
            .joined(separator: " ")
        recentPageTranslations.append(summary)
        if recentPageTranslations.count > 3 {
            recentPageTranslations.removeFirst()
        }
    }

    private func resetRecentContext() {
        recentPageTranslations = []
    }

    // Intermediate result of the page-preparation phase that happens before LLM translation.
    // Carries enough state for the finalize phase to either set the page result directly
    // (cache hit, skip, failure) or call the translation service in page-index order.
    private enum PagePreparation {
        case sameLanguageSkip
        case missingKey
        case cacheHit(bubbles: [TranslatedBubble], textPixelMask: CGImage?)
        case noMeaningfulBubbles(textPixelMask: CGImage?, imageHash: String)
        case ready(meaningful: [BubbleCluster], textPixelMask: CGImage?, imageHash: String, restoreFrom: MangaPage?)
        case failed(message: String, restoreFrom: MangaPage?)
    }

    var currentPage: MangaPage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var currentTranslations: [TranslatedBubble] {
        guard let page = currentPage, case .translated(let bubbles) = page.state else { return [] }
        return bubbles
    }

    var isCurrentPageProcessing: Bool {
        guard let page = currentPage, case .processing = page.state else { return false }
        return true
    }

    var translationService: any TranslationService {
        if let override = translationServiceOverride { return override }
        switch preferences.translationEngine {
        case .deepL: return DeepLTranslationService(keychainService: keychainService)
        case .google: return GoogleTranslationService(keychainService: keychainService)
        case .openAI: return OpenAITranslationService(model: preferences.openAIModel, baseURL: preferences.openAIBaseURL, keychainService: keychainService)
        case .githubCopilot: return CopilotTranslationService(model: preferences.copilotModel)
        }
    }

    // MARK: - Input Handling

    func handleInput(_ url: URL) async {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let ext = url.pathExtension.lowercased()

        if isDirectory {
            await loadFolder(url)
        } else if ext == "zip" || ext == "cbz" {
            await loadArchive(url)
        } else {
            await loadImage(url)
        }
    }

    // MARK: - Single image

    func loadImage(_ url: URL) async {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        self.sourcePath = url.path
        // Copy to temp to ensure accessibility after security scope is revoked
        let processedURL: URL
        do {
            processedURL = try FileInputService.copyToTemp(url)
        } catch {
            processedURL = url
        }
        if isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
        }

        resetRecentContext()
        var page = MangaPage(imageURL: processedURL)
        page.image = NSImage(contentsOf: processedURL)
        pages = [page]
        currentPageIndex = 0
        await translatePage(at: 0)
    }

    // MARK: - Batch

    func loadFolder(_ url: URL, displayPath: String? = nil) async {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        self.sourcePath = displayPath ?? url.path
        let imageURLs = FileInputService.scanFolder(url)
        pages = imageURLs.map { imageURL in
            var page = MangaPage(imageURL: imageURL)
            page.image = NSImage(contentsOf: imageURL)
            return page
        }
        if isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
        }
        resetRecentContext()
        currentPageIndex = 0
        cacheService.addHistory(path: url.path, pageCount: pages.count)
        await translateBatch()
    }

    func loadArchive(_ url: URL) async {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        do {
            let extractedURL = try FileInputService.extractArchive(url)
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
            await loadFolder(extractedURL, displayPath: url.path)
        } catch {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = "Failed to extract archive: \(error.localizedDescription)"
        }
    }

    private func translateBatch() async {
        await runBatchPipeline(bypassCache: false)
    }

    // MARK: - Translation pipeline

    func translatePage(at index: Int, bypassCache: Bool = false) async {
        guard pages.indices.contains(index) else { return }
        let service = translationService
        let usesContext = usesRecentPageContext(service.engine)
        let preparation = await preparePage(at: index, bypassCache: bypassCache, service: service)
        await finalizePage(at: index, preparation: preparation, service: service, usesRecentContext: usesContext)
    }

    // Phase A: bounded-concurrency preparation that does not consume or mutate recentPageTranslations.
    // Phase B: finalize translation either page-ordered (LLM engines) or concurrently (DeepL/Google).
    //
    // For context-consuming LLM engines this is the conservative "prep-all-then-finalize" shape.
    // A throughput-friendlier producer/consumer pipeline is deferred. See the
    // "Deferred Optimization: Producer/Consumer LLM Pipeline" section in
    // fix-batch-recent-context-order/design.md for the trade-offs.
    private func runBatchPipeline(bypassCache: Bool) async {
        isProcessing = true
        let service = translationService
        let usesContext = usesRecentPageContext(service.engine)

        if usesContext {
            var preparations: [PagePreparation?] = Array(repeating: nil, count: pages.count)
            await withTaskGroup(of: (Int, PagePreparation).self) { group in
                let maxConcurrent = 3
                var started = 0
                for i in pages.indices {
                    if started >= maxConcurrent {
                        if let result = await group.next() {
                            preparations[result.0] = result.1
                        }
                    }
                    started += 1
                    group.addTask { [weak self] in
                        guard let self else {
                            return (i, .failed(message: "view model deallocated", restoreFrom: nil))
                        }
                        let prep = await self.preparePage(at: i, bypassCache: bypassCache, service: service)
                        return (i, prep)
                    }
                }
                while let result = await group.next() {
                    preparations[result.0] = result.1
                }
            }
            for i in pages.indices {
                guard let prep = preparations[i] else { continue }
                await finalizePage(at: i, preparation: prep, service: service, usesRecentContext: true)
            }
        } else {
            await withTaskGroup(of: Void.self) { group in
                let maxConcurrent = 3
                var started = 0
                for i in pages.indices {
                    if started >= maxConcurrent {
                        await group.next()
                    }
                    started += 1
                    group.addTask { [weak self] in
                        guard let self else { return }
                        let prep = await self.preparePage(at: i, bypassCache: bypassCache, service: service)
                        await self.finalizePage(at: i, preparation: prep, service: service, usesRecentContext: false)
                    }
                }
            }
        }
        isProcessing = false
    }

    // Page preparation: does everything up to (but not including) the translation API call.
    // Returns intermediate state so the finalize phase can serialize translation calls
    // for context-consuming engines without holding up OCR work for other pages.
    private func preparePage(at index: Int, bypassCache: Bool, service: any TranslationService) async -> PagePreparation {
        guard pages.indices.contains(index) else {
            return .failed(message: "invalid page index", restoreFrom: nil)
        }

        let previousPage = pages[index]
        pages[index].state = .processing
        pages[index].textPixelMask = nil

        let restoreFrom: MangaPage?
        if bypassCache, case .translated = previousPage.state {
            restoreFrom = previousPage
        } else {
            restoreFrom = nil
        }

        guard preferences.sourceLanguage != preferences.targetLanguage else {
            pipelineLogger.log(
                "Page \(index + 1): skipped OCR and translation — source == target",
                level: .info,
                category: .pipeline,
                metadata: [
                    "page_index": "\(index + 1)",
                    "source_language": preferences.sourceLanguage.rawValue,
                    "target_language": preferences.targetLanguage.rawValue,
                    "reason": "same_language"
                ]
            )
            return .sameLanguageSkip
        }

        if translationServiceOverride == nil && service.engine != .githubCopilot {
            guard keychainService.hasKey(for: preferences.translationEngine) else {
                showMissingKeyAlert = true
                return .missingKey
            }
        }

        let imageURL = pages[index].imageURL

        let nsImage: NSImage
        if let cached = pages[index].image {
            nsImage = cached
        } else {
            guard let loaded = NSImage(contentsOf: imageURL) else {
                return .failed(message: "Failed to load image", restoreFrom: restoreFrom)
            }
            pages[index].image = loaded
            nsImage = loaded
        }

        let imageHash: String
        if let storedHash = pages[index].imageHash {
            imageHash = storedHash
        } else if let fileData = try? Data(contentsOf: imageURL) {
            imageHash = CacheService.imageHash(data: fileData)
            pages[index].imageHash = imageHash
        } else if let tiffData = nsImage.tiffRepresentation {
            imageHash = CacheService.imageHash(data: tiffData)
            pages[index].imageHash = imageHash
        } else {
            return .failed(message: "Failed to read image data", restoreFrom: restoreFrom)
        }

        if !bypassCache, let cached = cacheService.lookup(
            imageHash: imageHash,
            source: preferences.sourceLanguage,
            target: preferences.targetLanguage,
            engine: preferences.translationEngine
        ) {
            return .cacheHit(bubbles: cached.bubbles, textPixelMask: cached.textPixelMask)
        }

        do {
            let pageResult = try await ocrRouter.processPage(image: nsImage, sourceLanguage: preferences.sourceLanguage)
            let ordered = pageResult.bubbles
            let meaningful = ordered.filter { !$0.text.allSatisfy { $0.isPunctuation || $0.isWhitespace } }
            let skippedCount = ordered.count - meaningful.count
            if skippedCount > 0 {
                pipelineLogger.log(
                    "Page \(index + 1): filtered \(skippedCount) of \(ordered.count) meaningless bubble(s)",
                    level: .info,
                    category: .pipeline,
                    metadata: [
                        "page_index": "\(index + 1)",
                        "filtered_count": "\(skippedCount)",
                        "total_count": "\(ordered.count)"
                    ]
                )
            }
            if meaningful.isEmpty {
                pipelineLogger.log(
                    "Page \(index + 1): no meaningful bubbles after OCR — skipping translation",
                    level: .info,
                    category: .pipeline,
                    metadata: ["page_index": "\(index + 1)", "reason": "all_bubbles_meaningless"]
                )
                return .noMeaningfulBubbles(textPixelMask: pageResult.textPixelMask, imageHash: imageHash)
            }
            return .ready(
                meaningful: meaningful,
                textPixelMask: pageResult.textPixelMask,
                imageHash: imageHash,
                restoreFrom: restoreFrom
            )
        } catch {
            return .failed(message: error.localizedDescription, restoreFrom: restoreFrom)
        }
    }

    // Finalize a page: sets the final state and optionally appends to the recent-context window.
    // The recent-context window is mutated only when `usesRecentContext` is true (LLM engines).
    private func finalizePage(at index: Int, preparation: PagePreparation, service: any TranslationService, usesRecentContext: Bool) async {
        guard pages.indices.contains(index) else { return }

        switch preparation {
        case .sameLanguageSkip:
            pages[index].textPixelMask = nil
            pages[index].state = .translated([])

        case .missingKey:
            pages[index].state = .error("Missing API key for \(preferences.translationEngine.displayName)")

        case .cacheHit(let bubbles, let textPixelMask):
            pages[index].textPixelMask = textPixelMask
            pages[index].state = .translated(bubbles)
            appendToRecentContextIfNeeded(bubbles, usesRecentContext: usesRecentContext)

        case .noMeaningfulBubbles(let textPixelMask, let imageHash):
            pages[index].textPixelMask = textPixelMask
            pages[index].state = .translated([])
            cacheService.store(
                imageHash: imageHash,
                source: preferences.sourceLanguage,
                target: preferences.targetLanguage,
                engine: preferences.translationEngine,
                bubbles: [],
                textPixelMask: textPixelMask
            )
            appendToRecentContextIfNeeded([], usesRecentContext: usesRecentContext)

        case .ready(let meaningful, let textPixelMask, let imageHash, let restoreFrom):
            do {
                let context = buildTranslationContext(usesRecentContext: usesRecentContext)
                let output = try await service.translate(
                    bubbles: meaningful,
                    from: preferences.sourceLanguage,
                    to: preferences.targetLanguage,
                    context: context
                )
                if let glossaryID = activeGlossaryID, !output.detectedTerms.isEmpty {
                    glossaryService.insertDetectedTerms(output.detectedTerms, glossaryID: glossaryID)
                    glossaries = glossaryService.listGlossaries()
                }
                let translated = output.bubbles.sorted { $0.index < $1.index }
                cacheService.store(
                    imageHash: imageHash,
                    source: preferences.sourceLanguage,
                    target: preferences.targetLanguage,
                    engine: preferences.translationEngine,
                    bubbles: translated,
                    textPixelMask: textPixelMask
                )
                pages[index].textPixelMask = textPixelMask
                pages[index].state = .translated(translated)
                appendToRecentContextIfNeeded(translated, usesRecentContext: usesRecentContext)
            } catch {
                if let restoreFrom {
                    pages[index].state = restoreFrom.state
                    pages[index].textPixelMask = restoreFrom.textPixelMask
                } else {
                    pages[index].state = .error(error.localizedDescription)
                }
            }

        case .failed(let message, let restoreFrom):
            if let restoreFrom {
                pages[index].state = restoreFrom.state
                pages[index].textPixelMask = restoreFrom.textPixelMask
            } else {
                pages[index].state = .error(message)
            }
        }
    }

    func clearCacheAndResetPages() {
        cacheService.clearAll()
        for i in pages.indices {
            pages[i].state = .pending
            pages[i].textPixelMask = nil
        }
    }

    func translationCacheSize() -> Int64 {
        cacheService.translationCacheSize()
    }

    func dismissError(at index: Int) {
        guard pages.indices.contains(index), case .error = pages[index].state else { return }
        pages[index].textPixelMask = nil
        pages[index].state = .pending
    }

    func retranslateCurrentPage() async {
        await translatePage(at: currentPageIndex, bypassCache: true)
    }

    func retranslateAllPages() async {
        resetRecentContext()
        await runBatchPipeline(bypassCache: true)
    }

    // MARK: - Navigation

    func nextPage() {
        if currentPageIndex < pages.count - 1 {
            currentPageIndex += 1
            highlightedBubbleId = nil
        }
    }

    func previousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            highlightedBubbleId = nil
        }
    }
}
