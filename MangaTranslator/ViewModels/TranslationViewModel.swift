import SwiftUI
import AppKit

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var pages: [MangaPage] = []
    @Published var currentPageIndex: Int = 0
    @Published var highlightedBubbleId: UUID? = nil
    @Published var isProcessing = false
    @Published var errorMessage: String? = nil
    @Published var showMissingKeyAlert = false
    @Published var batchProgress: (completed: Int, total: Int) = (0, 0)
    @Published var preferences = PreferencesService()

    private let ocrRouter = OCRRouter()
    private let cacheService = CacheService()
    private let keychainService = KeychainService()

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

    var translationService: TranslationService {
        switch preferences.translationEngine {
        case .deepL: return DeepLTranslationService(keychainService: keychainService)
        case .google: return GoogleTranslationService(keychainService: keychainService)
        case .openAI: return OpenAITranslationService(model: preferences.openAIModel, baseURL: preferences.openAIBaseURL, keychainService: keychainService)
        case .claude: return ClaudeTranslationService(model: preferences.claudeModel, keychainService: keychainService)
        }
    }

    // MARK: - Single image

    func loadImage(_ url: URL) async {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
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
        
        pages = [MangaPage(imageURL: processedURL)]
        currentPageIndex = 0
        await translatePage(at: 0)
    }

    // MARK: - Batch

    func loadFolder(_ url: URL) async {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        let imageURLs = FileInputService.scanFolder(url)
        pages = imageURLs.map { MangaPage(imageURL: $0) }
        if isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
        }
        currentPageIndex = 0
        batchProgress = (0, pages.count)
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
            await loadFolder(extractedURL)
        } catch {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = "Failed to extract archive: \(error.localizedDescription)"
        }
    }

    private func translateBatch() async {
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
                    await self.translatePage(at: i)
                    await MainActor.run {
                        let count = self.pages.filter {
                            if case .translated = $0.state { return true }
                            return false
                        }.count
                        self.batchProgress.0 = count
                    }
                }
            }
        }
    }

    // MARK: - Translation pipeline

    func translatePage(at index: Int, bypassCache: Bool = false) async {
        guard pages.indices.contains(index) else { return }

        pages[index].state = .processing

        let needsTranslation = preferences.sourceLanguage != preferences.targetLanguage

        do {
            if needsTranslation {
                guard keychainService.hasKey(for: preferences.translationEngine) else {
                    showMissingKeyAlert = true
                    pages[index].state = .error("Missing API key for \(preferences.translationEngine.displayName)")
                    return
                }
            }

            let imageURL = pages[index].imageURL

            // Load image if not already cached
            let nsImage: NSImage
            if let cached = pages[index].image {
                nsImage = cached
            } else {
                guard let loaded = NSImage(contentsOf: imageURL) else {
                    pages[index].state = .error("Failed to load image")
                    return
                }
                pages[index].image = loaded
                nsImage = loaded
            }

            // Compute image hash (reuse stored hash if available)
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
                pages[index].state = .error("Failed to read image data")
                return
            }

            // Check cache
            if !bypassCache, let cached = cacheService.lookup(
                imageHash: imageHash,
                source: preferences.sourceLanguage,
                target: preferences.targetLanguage,
                engine: preferences.translationEngine
            ) {
                pages[index].state = .translated(cached)
                return
            }

            // OCR
            let ordered = try await ocrRouter.processPage(image: nsImage, sourceLanguage: preferences.sourceLanguage)

            // Skip translation if source == target or all bubbles are punctuation-only
            let translated: [TranslatedBubble]
            if preferences.sourceLanguage == preferences.targetLanguage || ordered.allSatisfy({ $0.text.allSatisfy { $0.isPunctuation || $0.isWhitespace } }) {
                translated = ordered.map { TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index) }
            } else {
                // Filter out punctuation-only bubbles from translation
                let toTranslate = ordered.filter { !$0.text.allSatisfy { $0.isPunctuation || $0.isWhitespace } }
                let punctuationOnly = ordered.filter { $0.text.allSatisfy { $0.isPunctuation || $0.isWhitespace } }

                let translatedResults = try await translationService.translate(
                    bubbles: toTranslate,
                    from: preferences.sourceLanguage,
                    to: preferences.targetLanguage
                )

                let passthrough = punctuationOnly.map { TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index) }
                translated = (translatedResults + passthrough).sorted { $0.index < $1.index }
            }

            // Cache
            cacheService.store(
                imageHash: imageHash,
                source: preferences.sourceLanguage,
                target: preferences.targetLanguage,
                engine: preferences.translationEngine,
                bubbles: translated
            )

            pages[index].state = .translated(translated)
        } catch {
            pages[index].state = .error(error.localizedDescription)
        }
    }

    func clearCacheAndResetPages() {
        cacheService.clearAll()
        for i in pages.indices {
            pages[i].state = .pending
        }
    }

    func retranslateCurrentPage() async {
        await translatePage(at: currentPageIndex, bypassCache: true)
    }

    func retranslateAllPages() async {
        batchProgress = (0, pages.count)
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
                    await self.translatePage(at: i, bypassCache: true)
                    await MainActor.run {
                        let count = self.pages.filter {
                            if case .translated = $0.state { return true }
                            return false
                        }.count
                        self.batchProgress.0 = count
                    }
                }
            }
        }
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