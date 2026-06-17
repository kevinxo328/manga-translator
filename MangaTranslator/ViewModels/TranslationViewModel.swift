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

    var ocrRouter: OCRRouter
    private let cacheService: any CacheServiceProtocol
    private let keychainService = KeychainService()
    private var cancellables = Set<AnyCancellable>()
    private let translationServiceOverride: (any TranslationService)?
    private let pipelineLogger: any PipelineLogging
    private let editModeOCROverride: (any EditModeOCRPerforming)?

    private var glossaryService: GlossaryService { cacheService.glossaryService }
    var glossaryServiceForView: GlossaryService { cacheService.glossaryService }
    private var recentPageTranslations: [String] = []
    private var cancellableTranslationTask: Task<Void, Never>?

    init(
        preferences: PreferencesService,
        ocrRouter: OCRRouter? = nil,
        translationService: (any TranslationService)? = nil,
        cacheService: (any CacheServiceProtocol)? = nil,
        pipelineLogger: any PipelineLogging = DebugLogger.shared,
        editModeOCR: (any EditModeOCRPerforming)? = nil
    ) {
        self.preferences = preferences
        self.translationServiceOverride = translationService
        self.pipelineLogger = pipelineLogger
        self.cacheService = cacheService ?? CacheService()
        self.editModeOCROverride = editModeOCR
        #if arch(arm64)
        self.ocrRouter = ocrRouter ?? OCRRouter.makeProductionRouter()
        #else
        self.ocrRouter = ocrRouter ?? OCRRouter()
        #endif
        glossaries = self.cacheService.glossaryService.listGlossaries()
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // The Edit Mode commit pipeline's per-region OCR provider. Defaults to
    // the live OCRRouter (which conforms to `EditModeOCRPerforming`) so
    // production reuses whichever recognizer the page's initial translation
    // already loaded. Tests override via the `editModeOCR:` init parameter.
    private var editModeOCR: any EditModeOCRPerforming {
        editModeOCROverride ?? ocrRouter
    }

    func loadGlossaries() {
        glossaries = glossaryService.listGlossaries()
    }

    @discardableResult
    func createAndSelectGlossary(named name: String) throws -> Glossary {
        let glossary = try glossaryService.createGlossary(name: name)
        loadGlossaries()
        activeGlossaryID = glossary.id
        return glossary
    }

    func renameGlossary(id: String, to newName: String) throws {
        try glossaryService.renameGlossary(id: id, newName: newName)
        loadGlossaries()
    }

    var activeGlossary: Glossary? {
        guard let id = activeGlossaryID else { return nil }
        return glossaries.first { $0.id == id }
    }

    // Engine boundary: only OpenAI-compatible and GitHub Copilot consume recent-page summaries.
    // DeepL and Google receive glossary terms but never recent-page context.
    private func usesRecentPageContext(_ engine: TranslationEngine) -> Bool {
        engine.isLLM
    }

    // Returns up to `count` summaries from translated pages whose index is
    // strictly less than `pageIndex`, in ascending page-index order. Pages
    // not in `.translated` are skipped (`.error`, `.pending`, `.processing`),
    // yielding fewer than `count` entries when not enough preceding pages
    // qualify. A page's summary is the concatenation of its
    // `TranslatedBubble.translatedText`s in `index` order joined by " ".
    //
    // Used by the Edit Mode Commit path so re-translation of page N sees
    // pages [N-3..<N] as its context — not the rolling-window buffer that
    // drives initial / batch translation. See
    // `openspec/changes/manual-bubble-editing/specs/contextual-translation/spec.md`.
    func summariesPreceding(pageIndex: Int, count: Int = 3) -> [String] {
        guard pageIndex > 0 else { return [] }
        let cap = min(pageIndex, pages.count)
        var qualifying: [String] = []
        for i in 0..<cap {
            guard case .translated(let bubbles) = pages[i].state else { continue }
            let summary = bubbles
                .sorted { $0.index < $1.index }
                .map { $0.translatedText }
                .joined(separator: " ")
            // Skip pages with no meaningful text (e.g. `.translated([])` from
            // the no-meaningful-bubbles path) so they don't occupy a slot.
            guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            qualifying.append(summary)
        }
        if qualifying.count <= count {
            return qualifying
        }
        return Array(qualifying.suffix(count))
    }

    // When `precedingPageIndex` is non-nil, sources `recentPageSummaries`
    // from `summariesPreceding(pageIndex:)` — the Edit Mode Commit path.
    // When nil, returns today's rolling-buffer behaviour used by initial
    // and batch translation. Non-context engines (DeepL, Google) always
    // receive empty summaries regardless.
    // Glossary terms are filtered to those occurring in `bubbles`' source
    // text, so prompt cost does not grow with the whole accumulated
    // glossary. The LLM may then re-report a filtered-out term as newly
    // detected; insertDetectedTerms dedupes against the full glossary.
    private func buildTranslationContext(
        matching bubbles: [BubbleCluster],
        usesRecentContext: Bool,
        precedingPageIndex: Int? = nil
    ) -> TranslationContext {
        let terms: [GlossaryTerm]
        if let id = activeGlossaryID {
            terms = GlossarySubstitution.relevantTerms(
                glossaryService.listTerms(glossaryID: id),
                in: bubbles.map { $0.text }
            )
        } else {
            terms = []
        }
        let summaries: [String]
        if !usesRecentContext {
            summaries = []
        } else if let index = precedingPageIndex {
            summaries = summariesPreceding(pageIndex: index)
        } else {
            summaries = recentPageTranslations
        }
        return TranslationContext(glossaryTerms: terms, recentPageSummaries: summaries)
    }

    private func appendToRecentContextIfNeeded(_ translated: [TranslatedBubble], usesRecentContext: Bool) {
        guard usesRecentContext else { return }
        let summary = translated
            .sorted { $0.index < $1.index }
            .map { $0.translatedText }
            .joined(separator: " ")
        // Pages with no meaningful text (title pages, pure artwork) must not
        // consume a slot in the rolling window — an empty summary evicts a
        // real one and degrades consistency on later pages.
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        recentPageTranslations.append(summary)
        if recentPageTranslations.count > 3 {
            recentPageTranslations.removeFirst()
        }
    }

    private func resetRecentContext() {
        recentPageTranslations = []
    }

    // Pipeline shape for a page translation request. `.standard` consults the
    // cache and runs full OCR on a miss; `.retranslate` bypasses the cache and
    // preserves any committed bubble set; `.engineSwitch` consults the new
    // engine's cache but only trusts entries whose layout matches the committed
    // set. See `openspec/changes/engine-switch-cache-reuse/design.md` D1.
    enum PageTranslationMode {
        case standard
        case retranslate
        case engineSwitch
    }

    // Layout comparison between a page's committed bubble set and a cached
    // entry, used by the engine-switch cache-hit gate. Translated text is
    // deliberately excluded: matching layouts with different translations are
    // exactly the case the lookup exists for. Exact CGRect equality, no
    // tolerance — same convention as the Edit Mode OCR-dirty rule. See
    // `openspec/changes/engine-switch-cache-reuse/design.md` D2.
    nonisolated static func layoutMatches(committed: [TranslatedBubble], cached: [TranslatedBubble]) -> Bool {
        guard committed.count == cached.count else { return false }
        let lhs = committed.sorted { $0.index < $1.index }
        let rhs = cached.sorted { $0.index < $1.index }
        return zip(lhs, rhs).allSatisfy { a, b in
            a.index == b.index
                && a.bubble.boundingBox == b.bubble.boundingBox
                && a.bubble.text == b.bubble.text
        }
    }

    // Intermediate result of the page-preparation phase that happens before LLM translation.
    // Carries enough state for the finalize phase to either set the page result directly
    // (cache hit, skip, failure) or call the translation service in page-index order.
    private enum PagePreparation {
        case sameLanguageSkip
        case missingKey
        case cacheHit(bubbles: [TranslatedBubble])
        case noMeaningfulBubbles(imageHash: String)
        case ready(meaningful: [BubbleCluster], imageHash: String, restoreFrom: MangaPage?)
        case failed(message: String, restoreFrom: MangaPage?)
    }

    // Sizing thresholds for the multi-page LLM batch scheduler. The constants are local
    // because the algorithm does not need to publish them; they are tuned with the engine
    // and the LLM context window in mind. See design.md Decision 3.
    private struct BatchSizingConfig {
        static let maxBubbles = 45
        static let maxPages = 5
    }

    // A single `.ready` page queued to be sent as part of a multi-page LLM batch.
    private struct BatchPlanItem {
        let pageIndex: Int
        let meaningful: [BubbleCluster]
        let imageHash: String
        let restoreFrom: MangaPage?
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

    // Unified lock for pipeline-affecting controls (Open, glossary, languages,
    // engine, Re-translate All). `isProcessing` covers the batch pipeline;
    // the page scan covers single-page flows (initial single image, sidebar
    // Re-translate, engine switch, Edit Mode commit), which mark only the
    // page itself `.processing`. See lock-controls-during-batch/design.md D1.
    var isTranslationInFlight: Bool {
        if isProcessing { return true }
        return pages.contains { if case .processing = $0.state { return true } else { return false } }
    }

    var canCancelTranslation: Bool {
        cancellableTranslationTask != nil && isTranslationInFlight
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
        guard editSession == nil else { return }
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
        guard editSession == nil else { return }
        // Single images are copied to temp below, so no lasting scope is
        // needed — but the folder the previous pages came from can let go.
        releaseSecurityScopedSource()
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
        guard editSession == nil else { return }
        // Pages hold only their URL; bitmaps load lazily (OCR in preparePage,
        // viewing via updateImageWindow). Reads happen long after this method
        // returns, so the folder's security scope must stay active for the
        // lifetime of the loaded pages — released when other content replaces
        // them — instead of ending here.
        releaseSecurityScopedSource()
        if url.startAccessingSecurityScopedResource() {
            securityScopedSourceURL = url
        }
        self.sourcePath = displayPath ?? url.path
        let imageURLs = FileInputService.scanFolder(url)
        pages = imageURLs.map { MangaPage(imageURL: $0) }
        resetRecentContext()
        currentPageIndex = 0
        updateImageWindow()
        await translateBatch()
    }

    func loadArchive(_ url: URL) async {
        guard editSession == nil else { return }
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
        await runBatchPipelineInCancellableTask(mode: .standard)
    }

    @discardableResult
    func startRetranslateAllPages() -> Task<Void, Never>? {
        guard cancellableTranslationTask == nil, !isTranslationInFlight, editSession == nil else { return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.cancellableTranslationTask = nil }
            self.resetRecentContext()
            await self.runBatchPipeline(mode: .retranslate)
        }
        cancellableTranslationTask = task
        return task
    }

    @discardableResult
    func startSwitchEngineForCurrentPage() -> Task<Void, Never>? {
        guard cancellableTranslationTask == nil, !isTranslationInFlight, editSession == nil else { return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.cancellableTranslationTask = nil }
            await self.switchEngineForCurrentPage()
        }
        cancellableTranslationTask = task
        return task
    }

    func cancelTranslation() {
        cancellableTranslationTask?.cancel()
    }

    private func runBatchPipelineInCancellableTask(mode: PageTranslationMode) async {
        guard cancellableTranslationTask == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runBatchPipeline(mode: mode)
        }
        cancellableTranslationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        cancellableTranslationTask = nil
    }

    // MARK: - Image memory window & source security scope

    // Security scope of the user-selected folder whose pages are currently
    // loaded. Lazy bitmap loads and hash reads occur long after loadFolder
    // returns and are only permitted while the scope is active.
    private var securityScopedSourceURL: URL?

    private func releaseSecurityScopedSource() {
        securityScopedSourceURL?.stopAccessingSecurityScopedResource()
        securityScopedSourceURL = nil
    }

    // Sliding window of decoded page images: only the current page, its
    // immediate neighbors, and an open Edit Mode page stay resident; other
    // pages keep just their URL and reload lazily when the window reaches
    // them. Bounds memory by window size instead of page count.
    private static let imageWindowRadius = 1

    private func isWithinImageWindow(_ index: Int) -> Bool {
        if abs(index - currentPageIndex) <= Self.imageWindowRadius { return true }
        // Edit Mode reads the page bitmap (commit OCR, pixel-size clamping);
        // never evict it while a session is open.
        if let sessionPageId = editSession?.pageId, pages[index].id == sessionPageId { return true }
        return false
    }

    private func updateImageWindow() {
        for index in pages.indices {
            if isWithinImageWindow(index) {
                if pages[index].image == nil {
                    pages[index].image = NSImage(contentsOf: pages[index].imageURL)
                }
            } else if pages[index].image != nil {
                pages[index].image = nil
            }
        }
    }

    // MARK: - Translation pipeline

    func translatePage(at index: Int, mode: PageTranslationMode = .standard) async {
        guard pages.indices.contains(index) else { return }
        let service = translationService
        let usesContext = usesRecentPageContext(service.engine)
        let preparation = await preparePage(at: index, mode: mode, service: service)
        await finalizePage(at: index, preparation: preparation, service: service, usesRecentContext: usesContext)
    }

    // Context-consuming LLM engines run a pipelined producer/consumer (below);
    // DeepL/Google keep their per-page parallel pipeline, which already starts
    // translating after each page's own preparation.
    private func runBatchPipeline(mode: PageTranslationMode) async {
        isProcessing = true
        defer { isProcessing = false }
        let service = translationService
        let usesContext = usesRecentPageContext(service.engine)

        if usesContext {
            await runPipelinedLLMBatch(mode: mode, service: service)
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
                        let prep = await self.preparePage(at: i, mode: mode, service: service)
                        await self.finalizePage(at: i, preparation: prep, service: service, usesRecentContext: false)
                    }
                }
            }
        }
    }

    // Ramp-up page caps for the pipelined LLM batch scheduler: the first group
    // ships after one page (time-to-first-page), the second after three, and
    // steady state uses the full cap — bounding the extra LLM calls versus
    // full-cap grouping to 2 per run. Group composition depends only on page
    // order, bubble counts, and preparation outcomes, never on OCR/LLM timing.
    // See producer-consumer-llm-pipeline/design.md D2.
    private func rampPageCap(forGroupOrdinal ordinal: Int) -> Int {
        switch ordinal {
        case 0: return 1
        case 1: return 3
        default: return BatchSizingConfig.maxPages
        }
    }

    // Pipelined producer/consumer for context-consuming LLM engines: the
    // bounded task group prepares pages (OCR, cache lookup) while a consumer
    // woven into the same loop drains results strictly in ascending page
    // index, so rolling-window observations keep the page-ordered guarantees
    // of contextual-translation. The first LLM request leaves as soon as
    // page 1's preparation is consumable; preparations continue while LLM
    // requests are in flight. See producer-consumer-llm-pipeline/design.md D1.
    private func runPipelinedLLMBatch(mode: PageTranslationMode, service: any TranslationService) async {
        var buffer: [Int: PagePreparation] = [:]
        var nextIndex = 0
        var currentGroup: [BatchPlanItem] = []
        var currentBubbleCount = 0
        var dispatchedGroupCount = 0
        var cancelled = false

        // Dispatches the accumulated group and advances the ramp ordinal.
        // Returns true when the run was cancelled.
        func dispatchCurrentGroup() async -> Bool {
            guard !currentGroup.isEmpty else { return false }
            let wasCancelled = await runBatch(currentGroup, service: service)
            currentGroup.removeAll()
            currentBubbleCount = 0
            dispatchedGroupCount += 1
            return wasCancelled
        }

        // Consumes buffered preparations in ascending page index. A missing
        // buffer entry for `nextIndex` stops the drain — later results stay
        // buffered until the gap fills, which is what keeps consumption
        // page-ordered regardless of preparation completion order.
        func consumeBuffered() async {
            while !cancelled, let prep = buffer[nextIndex] {
                buffer[nextIndex] = nil
                switch prep {
                case .ready(let meaningful, let hash, let restore):
                    let wouldExceedBubbles = currentBubbleCount + meaningful.count > BatchSizingConfig.maxBubbles
                    if !currentGroup.isEmpty && wouldExceedBubbles {
                        cancelled = await dispatchCurrentGroup()
                        if cancelled { return }
                    }
                    currentGroup.append(BatchPlanItem(
                        pageIndex: nextIndex,
                        meaningful: meaningful,
                        imageHash: hash,
                        restoreFrom: restore
                    ))
                    currentBubbleCount += meaningful.count
                    nextIndex += 1
                    if currentGroup.count >= rampPageCap(forGroupOrdinal: dispatchedGroupCount) {
                        cancelled = await dispatchCurrentGroup()
                    }
                default:
                    // Cache hits, skips, and failures finalize individually,
                    // act as group boundaries, and do not consume a ramp slot.
                    if !currentGroup.isEmpty {
                        cancelled = await dispatchCurrentGroup()
                        if cancelled { return }
                    }
                    await finalizePage(at: nextIndex, preparation: prep, service: service, usesRecentContext: true)
                    nextIndex += 1
                }
            }
        }

        await withTaskGroup(of: (Int, PagePreparation).self) { group in
            let maxConcurrent = 3
            var started = 0
            for i in pages.indices {
                if cancelled { break }
                if started >= maxConcurrent {
                    if let result = await group.next() {
                        buffer[result.0] = result.1
                        await consumeBuffered()
                    }
                }
                started += 1
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled else {
                        return (i, .failed(message: "view model deallocated", restoreFrom: nil))
                    }
                    let prep = await self.preparePage(at: i, mode: mode, service: service)
                    return (i, prep)
                }
            }
            if cancelled {
                group.cancelAll()
            }
            while let result = await group.next() {
                buffer[result.0] = result.1
                if !cancelled {
                    await consumeBuffered()
                    if cancelled {
                        group.cancelAll()
                    }
                }
            }
        }

        if !cancelled {
            // Page list exhausted: ship the final partial group.
            _ = await dispatchCurrentGroup()
        } else {
            // Post-quiescence revert sweep: the producer group has fully
            // drained above, so no late preparation can overwrite these
            // transitions. Every page that has not finalized — in the
            // cancelled batch (already reverted by runBatch), prepared but
            // unconsumed, or still mid-preparation — returns to .pending.
            // Pages finalized before the cancel keep their state.
            for i in pages.indices {
                if case .processing = pages[i].state {
                    pages[i].state = .pending
                }
            }
        }
    }

    // Page preparation: does everything up to (but not including) the translation API call.
    // Returns intermediate state so the finalize phase can serialize translation calls
    // for context-consuming engines without holding up OCR work for other pages.
    private func preparePage(at index: Int, mode: PageTranslationMode, service: any TranslationService) async -> PagePreparation {
        guard pages.indices.contains(index) else {
            return .failed(message: "invalid page index", restoreFrom: nil)
        }
        // Window membership is evaluated at exit so a page the user navigated
        // to while its OCR was in flight stays resident.
        defer {
            if pages.indices.contains(index), !isWithinImageWindow(index) {
                pages[index].image = nil
            }
        }

        // Snapshot for restore-on-failure, with the decoded bitmap stripped:
        // the restore path reads only `.state`, and a retained image would pin
        // bitmaps inside the pipelined prep buffer for the whole batch run.
        var previousPage = pages[index]
        previousPage.image = nil
        pages[index].state = .processing

        let restoreFrom: MangaPage?
        if mode != .standard, case .translated = previousPage.state {
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

        // `.standard` and `.engineSwitch` consult the cache; `.retranslate`
        // never does. An engine switch only trusts a cached entry whose layout
        // matches the page's committed bubble set — a stale layout (bubbles
        // drawn, moved, deleted, or reordered since the entry was written)
        // falls through to the preserve-and-retranslate branch below. See
        // `openspec/changes/engine-switch-cache-reuse/design.md` D2/D3.
        if mode != .retranslate, let cached = cacheService.lookup(
            imageHash: imageHash,
            source: preferences.sourceLanguage,
            target: preferences.targetLanguage,
            engine: preferences.translationEngine
        ) {
            if case .translated(let existing) = previousPage.state, !existing.isEmpty, mode == .engineSwitch {
                if Self.layoutMatches(committed: existing, cached: cached.bubbles) {
                    return .cacheHit(bubbles: cached.bubbles)
                }
                // Stale layout: fall through to the preserve branch.
            } else {
                return .cacheHit(bubbles: cached.bubbles)
            }
        }

        // Re-translate path: when the page already has a committed
        // `[TranslatedBubble]`, reuse it verbatim instead of re-running
        // bubble detection. This preserves every bubble's `boundingBox`,
        // `text`, `index`, and `isManual` flag across re-translate — so
        // drawn bubbles, moved/resized bubbles, and reordered sequences
        // all survive engine switches and explicit Re-translate clicks.
        // See `openspec/changes/manual-bubble-editing/specs/retranslate/spec.md`
        // (MODIFIED requirement) and `design.md` §D5.
        if mode != .standard, case .translated(let existing) = previousPage.state, !existing.isEmpty {
            var preservedClusters = existing
                .sorted { $0.index < $1.index }
                .map { $0.bubble }
            EditAction.redensifyIndices(&preservedClusters)
            pipelineLogger.log(
                "Page \(index + 1): re-translate preserving \(preservedClusters.count) committed bubble(s); skipping OCR",
                level: .info,
                category: .pipeline,
                metadata: [
                    "page_index": "\(index + 1)",
                    "preserved_count": "\(preservedClusters.count)",
                    "manual_count": "\(preservedClusters.filter { $0.isManual }.count)",
                    "reason": "retranslate_preserve_committed"
                ]
            )
            return .ready(
                meaningful: preservedClusters,
                imageHash: imageHash,
                restoreFrom: restoreFrom
            )
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
                return .noMeaningfulBubbles(imageHash: imageHash)
            }
            return .ready(
                meaningful: meaningful,
                imageHash: imageHash,
                restoreFrom: restoreFrom
            )
        } catch {
            return .failed(message: error.localizedDescription, restoreFrom: restoreFrom)
        }
    }

    // Run one multi-page LLM batch. Returns true if the run was cancelled, signalling the
    // caller to stop processing later batches. On non-cancellation failure, falls back to
    // calling the per-page translate(...) for every page in the group in page-index order;
    // per-page fallback uses the same recent-context window updates as the per-page entry.
    private func runBatch(_ group: [BatchPlanItem], service: any TranslationService) async -> Bool {
        guard !group.isEmpty else { return false }
        let pageInputs = group.map {
            BatchPageInput(pageId: String($0.pageIndex), bubbles: $0.meaningful)
        }
        let priorContext = buildTranslationContext(
            matching: group.flatMap { $0.meaningful },
            usesRecentContext: true
        )
        let itemByPageId = Dictionary(uniqueKeysWithValues: group.map { (String($0.pageIndex), $0) })

        do {
            let outputs = try await service.translateBatch(
                pageInputs: pageInputs,
                from: preferences.sourceLanguage,
                to: preferences.targetLanguage,
                priorContext: priorContext
            )
            // Cancellation may have arrived after the API call returned but before persist;
            // honour it so a cancelled batch never writes to pages, cache, or rolling window.
            if Task.isCancelled {
                revertBatchPagesToPending(group)
                return true
            }
            // Apply outputs in page-index order so the rolling window accumulates correctly.
            for output in outputs {
                guard let item = itemByPageId[output.pageId] else { continue }
                persistBatchOutput(output, item: item)
            }
            return false
        } catch let urlError as URLError where urlError.code == .cancelled {
            revertBatchPagesToPending(group)
            return true
        } catch is CancellationError {
            revertBatchPagesToPending(group)
            return true
        } catch {
            pipelineLogger.log(
                "Batch failed; falling back to per-page (pages=\(group.count))",
                level: .warning,
                category: .pipeline,
                metadata: [
                    "operation": "batchFallback",
                    "page_count": "\(group.count)",
                    "error": error.localizedDescription
                ]
            )
            // Per-page fallback: call the existing finalize path for each page, which
            // invokes service.translate(...) and updates the rolling window in order.
            for item in group {
                if Task.isCancelled {
                    revertRemainingBatchPagesToPending(group, startingAt: item.pageIndex)
                    return true
                }
                await finalizePage(
                    at: item.pageIndex,
                    preparation: .ready(
                        meaningful: item.meaningful,
                        imageHash: item.imageHash,
                        restoreFrom: item.restoreFrom
                    ),
                    service: service,
                    usesRecentContext: true
                )
            }
            return false
        }
    }

    private func persistBatchOutput(_ output: BatchPageOutput, item: BatchPlanItem) {
        if let glossaryID = activeGlossaryID, !output.detectedTerms.isEmpty {
            do {
                try glossaryService.insertDetectedTerms(output.detectedTerms, glossaryID: glossaryID)
                glossaries = glossaryService.listGlossaries()
            } catch {
                logCacheMutationFailure(error, operation: "GlossaryService.insertDetectedTerms")
            }
        }
        let translated = output.bubbles.sorted { $0.index < $1.index }
        do {
            try cacheService.store(
                imageHash: item.imageHash,
                source: preferences.sourceLanguage,
                target: preferences.targetLanguage,
                engine: preferences.translationEngine,
                bubbles: translated
            )
        } catch {
            logCacheMutationFailure(error, operation: "CacheService.store")
        }
        pages[item.pageIndex].state = .translated(translated)
        appendToRecentContextIfNeeded(translated, usesRecentContext: true)
    }

    private func revertBatchPagesToPending(_ group: [BatchPlanItem]) {
        for item in group where pages.indices.contains(item.pageIndex) {
            pages[item.pageIndex].state = .pending
        }
    }

    private func revertRemainingBatchPagesToPending(_ group: [BatchPlanItem], startingAt index: Int) {
        for item in group where item.pageIndex >= index && pages.indices.contains(item.pageIndex) {
            pages[item.pageIndex].state = .pending
        }
    }

    // Finalize a page: sets the final state and optionally appends to the recent-context window.
    // The recent-context window is mutated only when `usesRecentContext` is true (LLM engines).
    private func finalizePage(at index: Int, preparation: PagePreparation, service: any TranslationService, usesRecentContext: Bool) async {
        guard pages.indices.contains(index) else { return }

        switch preparation {
        case .sameLanguageSkip:
            pages[index].state = .translated([])

        case .missingKey:
            pages[index].state = .error("Missing API key for \(preferences.translationEngine.displayName)")

        case .cacheHit(let bubbles):
            pages[index].state = .translated(bubbles)
            appendToRecentContextIfNeeded(bubbles, usesRecentContext: usesRecentContext)

        case .noMeaningfulBubbles(let imageHash):
            pages[index].state = .translated([])
            do {
                try cacheService.store(
                    imageHash: imageHash,
                    source: preferences.sourceLanguage,
                    target: preferences.targetLanguage,
                    engine: preferences.translationEngine,
                    bubbles: []
                )
            } catch {
                logCacheMutationFailure(error, operation: "CacheService.store")
            }
        case .ready(let meaningful, let imageHash, let restoreFrom):
            do {
                let context = buildTranslationContext(matching: meaningful, usesRecentContext: usesRecentContext)
                let output = try await service.translate(
                    bubbles: meaningful,
                    from: preferences.sourceLanguage,
                    to: preferences.targetLanguage,
                    context: context
                )
                if let glossaryID = activeGlossaryID, !output.detectedTerms.isEmpty {
                    do {
                        try glossaryService.insertDetectedTerms(output.detectedTerms, glossaryID: glossaryID)
                        glossaries = glossaryService.listGlossaries()
                    } catch {
                        logCacheMutationFailure(error, operation: "GlossaryService.insertDetectedTerms")
                    }
                }
                let translated = output.bubbles.sorted { $0.index < $1.index }
                do {
                    try cacheService.store(
                        imageHash: imageHash,
                        source: preferences.sourceLanguage,
                        target: preferences.targetLanguage,
                        engine: preferences.translationEngine,
                        bubbles: translated
                    )
                } catch {
                    logCacheMutationFailure(error, operation: "CacheService.store")
                }
                pages[index].state = .translated(translated)
                appendToRecentContextIfNeeded(translated, usesRecentContext: usesRecentContext)
            } catch {
                if let restoreFrom {
                    pages[index].state = restoreFrom.state
                } else {
                    pages[index].state = .error(error.localizedDescription)
                }
            }

        case .failed(let message, let restoreFrom):
            if let restoreFrom {
                pages[index].state = restoreFrom.state
            } else {
                pages[index].state = .error(message)
            }
        }
    }

    func clearCacheAndResetPages() {
        do {
            try cacheService.clearAll()
            for i in pages.indices {
                pages[i].state = .pending
            }
        } catch {
            errorMessage = "Failed to clear cache. Translations may still be cached. Please restart the app if the problem persists."
            logCacheMutationFailure(error, operation: "CacheService.clearAll")
        }
    }

    // Centralises the SQLite-message → DebugLogger routing so UI surfaces never
    // see raw database internals. Mutation callers that must keep working (e.g.
    // store during translation) call this with try/catch and never alter the
    // page state machine.
    private func logCacheMutationFailure(_ error: Error, operation: String) {
        logCacheMutationFailure(error, operation: operation, level: .error)
    }

    private func logCacheMutationFailure(_ error: Error, operation: String, level: DebugLogLevel) {
        if let cacheError = error as? CacheError {
            switch cacheError {
            case .unavailable:
                pipelineLogger.log(
                    "\(operation): cache unavailable",
                    level: level,
                    category: .cache,
                    kind: .operational,
                    metadata: ["operation": operation, "reason": "unavailable"],
                    filePath: nil,
                    source: #fileID
                )
            case .sqlite(let code, let message, let op):
                pipelineLogger.log(
                    "\(operation): SQLite error in \(op): \(message)",
                    level: level,
                    category: .cache,
                    kind: .operational,
                    metadata: [
                        "operation": operation,
                        "sqlite_operation": op,
                        "sqlite_code": "\(code)",
                        "sqlite_message": message
                    ],
                    filePath: nil,
                    source: #fileID
                )
            }
        } else {
            pipelineLogger.log(
                "\(operation): \(error.localizedDescription)",
                level: level,
                category: .cache,
                kind: .operational,
                metadata: ["operation": operation],
                filePath: nil,
                source: #fileID
            )
        }
    }

    func translationCacheSize() -> Int64 {
        cacheService.translationCacheSize()
    }

    func dismissError(at index: Int) {
        guard pages.indices.contains(index), case .error = pages[index].state else { return }
        pages[index].state = .pending
    }

    func retranslateCurrentPage() async {
        guard editSession == nil else { return }
        await translatePage(at: currentPageIndex, mode: .retranslate)
    }

    // Entry point for the toolbar engine picker's onChange. Unlike the explicit
    // Re-translate button this consults the new engine's cache, so flipping
    // back to a previously used engine is free when the layout still matches.
    func switchEngineForCurrentPage() async {
        guard editSession == nil else { return }
        // The toolbar engine picker is disabled while translation is in
        // flight, but the Settings window mutates the same preference and
        // fires the same onChange, so the guard must live here. The ignored
        // switch is not replayed; the next translation picks up the new
        // engine. See lock-controls-during-batch/design.md D2/D3.
        guard !isTranslationInFlight else { return }
        await translatePage(at: currentPageIndex, mode: .engineSwitch)
    }

    func retranslateAllPages() async {
        guard editSession == nil else { return }
        resetRecentContext()
        await runBatchPipelineInCancellableTask(mode: .retranslate)
    }

    // MARK: - Navigation

    func nextPage() {
        guard editSession == nil else { return }
        if currentPageIndex < pages.count - 1 {
            currentPageIndex += 1
            highlightedBubbleId = nil
            updateImageWindow()
        }
    }

    func previousPage() {
        guard editSession == nil else { return }
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            highlightedBubbleId = nil
            updateImageWindow()
        }
    }

    // MARK: - Edit Mode

    // The currently-open edit session, or nil when no session is active.
    // Read by views to drive Edit Mode UI; written only by the lifecycle
    // methods below (`openEditSession`, `cancelEditSession`,
    // `applyEditAction`, `undo`, `redo`, `commitEditSession`).
    @Published private(set) var editSession: EditSession?

    // True while `commitEditSession()` is mid-flight (OCR + translate). UI
    // uses this to disable the Done / Cancel buttons so the user cannot
    // double-fire the pipeline. On Failure this flag goes back to false
    // with the session still open, so Done / Cancel become live again for
    // retry / abort.
    @Published private(set) var isCommittingEditSession: Bool = false

    // Opens a per-page Edit Mode session. Rejected if `pageId` is not a
    // current page OR the page is not in `.translated` state — Edit Mode is
    // a transactional editor over already-translated bubbles. Captures both
    // the bubble snapshot and the PageState so Cancel can restore the page
    // verbatim even after a failed Commit (which would leave the page in
    // `.error`). See
    // `openspec/changes/manual-bubble-editing/design.md` §D1.
    func openEditSession(pageId: UUID) {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }
        guard case .translated(let bubbles) = pages[pageIndex].state else { return }
        let working = bubbles.map { $0.bubble }
        editSession = EditSession(
            pageId: pageId,
            workingBubbles: working,
            originalSnapshot: bubbles,
            originalPageState: pages[pageIndex].state
        )
    }

    // Discards the current Edit Mode session. Restores both the page's
    // `[TranslatedBubble]` (from `originalSnapshot`) AND the page's
    // PageState (from `originalPageState`). The PageState restore matters
    // when a prior Commit attempt failed and left the page in `.error`:
    // Cancel exits Edit Mode AND clears that error in one step. No cache
    // write occurs on Cancel.
    func cancelEditSession() {
        guard let session = editSession else { return }
        if let pageIndex = pages.firstIndex(where: { $0.id == session.pageId }) {
            pages[pageIndex].state = session.originalPageState
        }
        editSession = nil
    }

    // Applies `action` to the working copy, pushes it onto the undo stack,
    // and clears the redo stack. The forward apply path dispatches on the
    // action variant per the table in `design.md` §D2 — notably `.add` uses
    // `ReadingOrderSorter.insertNearestNeighbour(_:into:)` so newly drawn
    // bubbles land at their geometric position rather than at the end of
    // the list. No-op if no edit session is open.
    func applyEditAction(_ action: EditAction) {
        guard !isCommittingEditSession else { return }
        guard var session = editSession else { return }
        Self.applyForward(action, to: &session)
        session.undoStack.append(action)
        session.redoStack.removeAll()
        editSession = session
    }

    // Reverses the top of the undo stack and pushes it onto the redo stack.
    // The inverse is dispatched via `EditAction.applyInverse(to:)` which
    // only restores `boundingBox` for `.move`/`.resize` — `isManual` stays
    // sticky once set (§D5). No-op when the undo stack is empty.
    func undo() {
        guard !isCommittingEditSession else { return }
        guard var session = editSession,
              let action = session.undoStack.popLast() else { return }
        action.applyInverse(to: &session)
        session.redoStack.append(action)
        editSession = session
    }

    // Re-applies the top of the redo stack through the same forward apply
    // path as the original mutation, then pushes it onto the undo stack.
    // No-op when the redo stack is empty.
    func redo() {
        guard !isCommittingEditSession else { return }
        guard var session = editSession,
              let action = session.redoStack.popLast() else { return }
        Self.applyForward(action, to: &session)
        session.undoStack.append(action)
        editSession = session
    }

    // Commits the open edit session per `design.md` §D10.
    //
    // Terminal branches (mutually exclusive, only one fires per call):
    //   - **Empty**:   final working set is empty → state `.translated([])`,
    //                  session cleared, no OCR, no translator call, cache
    //                  best-effort with `[]`. Never enters `.processing`.
    //   - **Success**: OCR + translate both succeed → state `.translated(output.bubbles)`,
    //                  session cleared, cache best-effort with output.
    //   - **Failure**: OCR or translator throws → state `.error(...)`,
    //                  session preserved so the user can retry or cancel.
    //
    // Cache writes are best-effort throughout: thrown errors are logged at
    // warning level via DebugLogger and do NOT roll back the in-memory
    // commit. See `design.md` §D10 for rationale.
    //
    // Uses `summariesPreceding(pageIndex:)` to source the translation
    // context — the rolling recent-context window used by initial / batch
    // translation is deliberately ignored on this code path and SHALL NOT
    // be appended to after a successful commit. The Re-translate button
    // path continues to use the rolling window.
    func commitEditSession() async {
        guard let session = editSession else { return }
        guard !isCommittingEditSession else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.id == session.pageId }) else {
            editSession = nil
            return
        }
        isCommittingEditSession = true
        defer { isCommittingEditSession = false }

        // Steps 1–2: compute the final working set with redensified indices.
        var workingOrdered = session.workingBubbles.filter { !session.deletedBubbleIds.contains($0.id) }
        EditAction.redensifyIndices(&workingOrdered)

        // Step 3: final-state no-op short-circuit. If the user ends at the
        // same bubble ids, order, and geometry captured at session open,
        // Done only closes Edit Mode. In-session sticky flags such as
        // `isManual` are treated as transient unless another content change
        // is actually committed.
        if Self.matchesOriginalEditSnapshot(workingOrdered, originalSnapshot: session.originalSnapshot) {
            pages[pageIndex].state = session.originalPageState
            editSession = nil
            return
        }

        // Step 4: empty-set short-circuit — skip OCR, skip translator, skip
        // .processing. The result is independent of API-key / network state.
        if workingOrdered.isEmpty {
            if let hash = pages[pageIndex].imageHash {
                do {
                    try cacheService.store(
                        imageHash: hash,
                        source: preferences.sourceLanguage,
                        target: preferences.targetLanguage,
                        engine: preferences.translationEngine,
                        bubbles: []
                    )
                } catch {
                    logCacheMutationFailure(error, operation: "CacheService.store [edit commit empty]", level: .warning)
                }
            }
            pages[pageIndex].state = .translated([])
            editSession = nil
            return
        }

        // Step 5: classify OCR-dirty using final-geometry-vs-snapshot diff.
        // `dirtyBubbleIds` is a UI cache and is NOT consulted here (§D3).
        let snapshotByID = Dictionary(uniqueKeysWithValues: session.originalSnapshot.map {
            ($0.bubble.id, $0.bubble)
        })
        let dirtyBubbles = workingOrdered.filter { bubble in
            guard let snapshot = snapshotByID[bubble.id] else { return true } // new
            return bubble.boundingBox != snapshot.boundingBox                  // geometry-changed
        }

        // Step 6: enter .processing only on the non-empty, non-no-op path.
        pages[pageIndex].state = .processing

        // Step 7: run OCR over the dirty subset.
        var ocrResults: [UUID: String] = [:]
        if !dirtyBubbles.isEmpty {
            guard let image = pages[pageIndex].image else {
                pages[pageIndex].state = .error("Page image unavailable for OCR")
                return
            }
            do {
                ocrResults = try await editModeOCR.recognizeRegions(
                    image: image,
                    bubbles: dirtyBubbles,
                    sourceLanguage: preferences.sourceLanguage
                )
            } catch {
                pages[pageIndex].state = .error(error.localizedDescription)
                return
            }
        }

        // Step 8: assemble the merged bubble set in the user's current order.
        // Dirty bubbles get fresh OCR text; clean bubbles reuse their
        // snapshot text. Both are then re-translated.
        let merged = workingOrdered.map { bubble -> BubbleCluster in
            if let freshText = ocrResults[bubble.id] {
                return bubble.withText(freshText)
            }
            if let snapshot = snapshotByID[bubble.id] {
                return bubble.withText(snapshot.text)
            }
            return bubble
        }

        // Steps 9–10: build the indexed context and translate the whole page.
        let service = translationService
        let usesContext = usesRecentPageContext(service.engine)
        let context = buildTranslationContext(
            matching: merged,
            usesRecentContext: usesContext,
            precedingPageIndex: pageIndex
        )
        let output: TranslationOutput
        do {
            output = try await service.translate(
                bubbles: merged,
                from: preferences.sourceLanguage,
                to: preferences.targetLanguage,
                context: context
            )
        } catch {
            pages[pageIndex].state = .error(error.localizedDescription)
            return
        }

        // Step 11: cache (best-effort). Failures are logged but do not
        // affect the user-visible commit.
        if let hash = pages[pageIndex].imageHash {
            do {
                try cacheService.store(
                    imageHash: hash,
                    source: preferences.sourceLanguage,
                    target: preferences.targetLanguage,
                    engine: preferences.translationEngine,
                    bubbles: output.bubbles
                )
            } catch {
                logCacheMutationFailure(error, operation: "CacheService.store [edit commit]", level: .warning)
            }
        }

        // Step 12: atomic in-memory swap. Note we do NOT append to the
        // rolling recent-context window — that buffer belongs to the
        // initial / batch translation flow.
        pages[pageIndex].state = .translated(output.bubbles)
        editSession = nil
    }

    private static func matchesOriginalEditSnapshot(
        _ workingOrdered: [BubbleCluster],
        originalSnapshot: [TranslatedBubble]
    ) -> Bool {
        guard workingOrdered.count == originalSnapshot.count else { return false }
        for (working, original) in zip(workingOrdered, originalSnapshot) {
            if working.id != original.bubble.id { return false }
            if working.boundingBox != original.bubble.boundingBox { return false }
        }
        return true
    }

    // MARK: - Edit Mode selection + keyboard helpers

    // Replaces the current selection with `ids`. No-op when no session.
    func setSelection(_ ids: Set<UUID>) {
        guard !isCommittingEditSession else { return }
        guard var session = editSession else { return }
        session.selectedBubbleIds = ids
        editSession = session
    }

    // `Cmd+A` — selects every non-deleted bubble in the working copy.
    func selectAllBubbles() {
        guard !isCommittingEditSession else { return }
        guard var session = editSession else { return }
        let visible = session.workingBubbles.filter { !session.deletedBubbleIds.contains($0.id) }
        session.selectedBubbleIds = Set(visible.map(\.id))
        editSession = session
    }

    // `Tab` / `Shift+Tab` — moves the highlight by reading-order index.
    // Direction +1 picks the bubble whose index is one greater than the
    // highest currently-selected, wrapping to the lowest. Direction -1 is
    // symmetric. Empty selection → pick the boundary bubble.
    func cycleSelection(direction: Int) {
        guard !isCommittingEditSession else { return }
        guard var session = editSession else { return }
        let visible = session.workingBubbles
            .filter { !session.deletedBubbleIds.contains($0.id) }
            .sorted { $0.index < $1.index }
        guard !visible.isEmpty else { return }

        if session.selectedBubbleIds.isEmpty {
            let pick = direction > 0 ? visible.first! : visible.last!
            session.selectedBubbleIds = [pick.id]
            editSession = session
            return
        }
        let pivotIndex: Int = direction > 0
            ? (visible.compactMap { session.selectedBubbleIds.contains($0.id) ? $0.index : nil }.max() ?? -1)
            : (visible.compactMap { session.selectedBubbleIds.contains($0.id) ? $0.index : nil }.min() ?? visible.count)
        let nextIndex: Int
        if direction > 0 {
            nextIndex = pivotIndex + 1 < visible.count ? pivotIndex + 1 : 0
        } else {
            nextIndex = pivotIndex - 1 >= 0 ? pivotIndex - 1 : visible.count - 1
        }
        let pick = visible.first { $0.index == nextIndex } ?? visible.first!
        session.selectedBubbleIds = [pick.id]
        editSession = session
    }

    // `Delete` / `Backspace` — stages every currently-selected bubble for
    // deletion as a single `.multi` so undo restores them in one shot.
    func stageDeleteSelected() {
        guard !isCommittingEditSession else { return }
        guard let session = editSession, !session.selectedBubbleIds.isEmpty else { return }
        let targets = session.workingBubbles.filter { session.selectedBubbleIds.contains($0.id) }
        guard !targets.isEmpty else { return }
        if targets.count == 1 {
            applyEditAction(.delete(targets[0]))
        } else {
            applyEditAction(.multi(targets.map { .delete($0) }))
        }
    }

    // Arrow-key nudging — shifts every selected bubble by `(dx, dy)` image
    // pixels. Empty selection → no-op (the caller must NOT fall back to
    // page navigation; the page-navigation handler is suppressed while
    // editing, per the lifecycle spec). A single press across N bubbles
    // produces one `.multi` undo entry.
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard !isCommittingEditSession else { return }
        guard let session = editSession, !session.selectedBubbleIds.isEmpty else { return }
        let pixelSize = editImagePixelSize(for: session)
        var actions: [EditAction] = []
        for bubble in session.workingBubbles where session.selectedBubbleIds.contains(bubble.id) {
            let from = bubble.boundingBox
            var to = CGRect(
                x: from.origin.x + dx,
                y: from.origin.y + dy,
                width: from.width,
                height: from.height
            )
            if let pixelSize {
                to = Self.clampEditRect(to, pixelSize: pixelSize)
            }
            if to == from { continue }
            actions.append(.move(id: bubble.id, from: from, to: to))
        }
        if actions.isEmpty { return }
        if actions.count == 1 {
            applyEditAction(actions[0])
        } else {
            applyEditAction(.multi(actions))
        }
    }

    private func editImagePixelSize(for session: EditSession) -> CGSize? {
        guard let pageIndex = pages.firstIndex(where: { $0.id == session.pageId }),
              let image = pages[pageIndex].image else { return nil }
        if let rep = image.representations.first as? NSBitmapImageRep,
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    private static func clampEditRect(_ rect: CGRect, pixelSize: CGSize) -> CGRect {
        var clamped = rect
        if clamped.size.width > pixelSize.width { clamped.size.width = pixelSize.width }
        if clamped.size.height > pixelSize.height { clamped.size.height = pixelSize.height }
        if clamped.origin.x < 0 { clamped.origin.x = 0 }
        if clamped.origin.y < 0 { clamped.origin.y = 0 }
        if clamped.maxX > pixelSize.width { clamped.origin.x = pixelSize.width - clamped.size.width }
        if clamped.maxY > pixelSize.height { clamped.origin.y = pixelSize.height - clamped.size.height }
        return clamped
    }

    // Esc cascade levels 2 + 3 per the lifecycle spec. Level 1 (abort an
    // in-flight gesture) lives in `ImageViewer` because the gesture state
    // is local to that view. ContentView calls this after the gesture
    // layer has had its chance.
    //
    //   - Selection non-empty: clear selection only, keep the session.
    //   - Selection empty: trigger Cancel (which restores `originalSnapshot`
    //     and `originalPageState`, clearing any prior `.error` state).
    func handleEscapeCascade() {
        guard !isCommittingEditSession else { return }
        guard let session = editSession else { return }
        if !session.selectedBubbleIds.isEmpty {
            setSelection([])
        } else {
            cancelEditSession()
        }
    }

    // Pure mutation for the forward direction. Used by `applyEditAction`
    // (initial apply) and `redo`. Kept on `Self` so it can be reused
    // without re-binding `self` and can dispatch recursively for `.multi`.
    private static func applyForward(_ action: EditAction, to session: inout EditSession) {
        switch action {
        case .add(let bubble):
            // Geometric placement — see §D4. Replaces the working array
            // wholesale because indices are redensified `0..<n`.
            session.workingBubbles = ReadingOrderSorter.insertNearestNeighbour(
                bubble, into: session.workingBubbles
            )
            // Newly drawn bubbles drive the "new" sidebar decoration via
            // membership in `originalSnapshot`, not via `dirtyBubbleIds`,
            // so this branch deliberately leaves the dirty cache alone.

        case .delete(let bubble):
            session.deletedBubbleIds.insert(bubble.id)

        case .unstageDelete(let bubble):
            session.deletedBubbleIds.remove(bubble.id)

        case .move(let id, _, let to), .resize(let id, _, let to):
            if let idx = session.workingBubbles.firstIndex(where: { $0.id == id }) {
                session.workingBubbles[idx].boundingBox = to
                // Sticky-flag flip — once true, stays true regardless of
                // subsequent edits or undo. §D5.
                if !session.workingBubbles[idx].isManual {
                    session.workingBubbles[idx].isManual = true
                }
                // UI-only dirty marker for the sidebar "Modified" badge.
                session.dirtyBubbleIds.insert(id)
            }

        case .reorder(_, let to):
            session.workingBubbles = EditAction.reorder(session.workingBubbles, byIds: to)
            EditAction.redensifyIndices(&session.workingBubbles)

        case .multi(let actions):
            for sub in actions {
                applyForward(sub, to: &session)
            }
        }
    }
}
