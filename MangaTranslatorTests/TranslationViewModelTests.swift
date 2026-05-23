import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

@MainActor
final class TranslationViewModelTests: XCTestCase {

    // MARK: - textPixelMask cleared on non-OCR paths

    func testSameLanguageClearsTextPixelMask() async {
        let prefs = makePrefs(source: .ja, target: .ja)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: TrackingTranslationService())
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/same-lang-mask.jpg"))
        page.image = makeTestImage()
        page.textPixelMask = makeTestCGImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)

        XCTAssertNil(vm.pages[0].textPixelMask, "Same-language path must clear stale textPixelMask")
    }

    func testCacheHitClearsTextPixelMask() async {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let router = await makeRouter(recognizerText: "こんにちは")
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: TrackingTranslationService())
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/cache-hit-mask.jpg"))
        page.image = makeTestImage()
        page.textPixelMask = makeTestCGImage()
        vm.pages = [page]

        // First pass populates the cache
        await vm.translatePage(at: 0, bypassCache: true)

        // Restore stale mask to simulate a second load scenario
        vm.pages[0].textPixelMask = makeTestCGImage()

        // Second pass hits the cache
        await vm.translatePage(at: 0)

        XCTAssertNil(vm.pages[0].textPixelMask, "Cache-hit path must clear stale textPixelMask")
    }

    // MARK: - 2. TDD — Same-language OCR skip

    func testSameLanguageSkipsOCRAndTranslation() async {
        // If OCR is reached, the throwing recognizer makes the page error out.
        let recognizer = ThrowingOCRRecognizer()
        let service = MangaOCRService(detector: MockComicTextDetectorSingle())
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
        )
        var translationCalled = false
        let translationService = TrackingTranslationService(onTranslate: { translationCalled = true })

        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.targetLanguage = .ja  // same as default source (.ja)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/same-lang.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)

        // OCR skipped → state is .translated, not .error
        guard case .translated(let bubbles) = vm.pages[0].state else {
            return XCTFail("Expected .translated([]), got \(vm.pages[0].state)")
        }
        XCTAssertTrue(bubbles.isEmpty, "Same-language page must produce no translated bubbles")
        XCTAssertFalse(translationCalled, "Translation must not be called for same-language page")
        // Guard fires before image-hash computation → imageHash stays nil
        XCTAssertNil(vm.pages[0].imageHash, "imageHash must not be set when same-language guard fires first")
    }

    // MARK: - Log metadata

    func testSameLanguageEmitsCorrectLogMetadata() async {
        let prefs = makePrefs(source: .ja, target: .ja)
        let logFixture = makeDebugLogFixture()
        defer { logFixture.cleanup() }
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            pipelineLogger: logFixture.logger
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/same-lang-log.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)
        await logFixture.logger.flush()

        var filter = DebugLogFilter()
        filter.category = .pipeline
        filter.sessionIDFilter = .session(logFixture.logger.sessionID)
        let entries = await logFixture.store.queryAll(filter: filter)
        let entry = entries.first { $0.metadataJSON.contains("same_language") }
        guard let entry else {
            return XCTFail("No pipeline log entry with reason:same_language found")
        }
        let meta = decodeMeta(entry.metadataJSON)
        XCTAssertEqual(meta["reason"], "same_language")
        XCTAssertEqual(meta["source_language"], "ja")
        XCTAssertEqual(meta["target_language"], "ja")
        XCTAssertEqual(meta["page_index"], "1")
    }

    func testMeaninglessFilterEmitsFilteredCountMetadata() async {
        let router = await makeRouter(recognizerText: "。")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let logFixture = makeDebugLogFixture()
        defer { logFixture.cleanup() }
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: TrackingTranslationService(),
            pipelineLogger: logFixture.logger
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/punct-log.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)
        await logFixture.logger.flush()

        var filter = DebugLogFilter()
        filter.category = .pipeline
        filter.sessionIDFilter = .session(logFixture.logger.sessionID)
        let entries = await logFixture.store.queryAll(filter: filter)
        let filterEntry = entries.first { $0.metadataJSON.contains("filtered_count") }
        guard let filterEntry else {
            return XCTFail("No pipeline log entry with filtered_count found")
        }
        let meta = decodeMeta(filterEntry.metadataJSON)
        XCTAssertEqual(meta["filtered_count"], "1")
        XCTAssertEqual(meta["total_count"], "1")
        XCTAssertEqual(meta["page_index"], "1")

        let skipEntry = entries.first { $0.metadataJSON.contains("all_bubbles_meaningless") }
        guard let skipEntry else {
            return XCTFail("No pipeline log entry with reason:all_bubbles_meaningless found")
        }
        XCTAssertEqual(decodeMeta(skipEntry.metadataJSON)["reason"], "all_bubbles_meaningless")
    }

    // MARK: - Empty-text bubble

    func testEmptyTextBubbleNotInSidebarAndSkipsTranslation() async {
        var translationCalled = false
        let router = await makeRouter(recognizerText: "")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true })
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/empty.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]
        await vm.translatePage(at: 0, bypassCache: true)
        guard case .translated(let bubbles) = vm.pages[0].state else {
            return XCTFail("Expected .translated, got \(vm.pages[0].state)")
        }
        XCTAssertTrue(bubbles.isEmpty, "Empty-text bubble must not appear in sidebar")
        XCTAssertFalse(translationCalled, "Translation must not be called when all bubbles have empty text")
    }

    // MARK: - 3. TDD — Meaningless bubble filter

    func testPunctuationOnlyBubblesNotInSidebar() async {
        let router = await makeRouter(recognizerText: "。")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: TrackingTranslationService())
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/punct.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]
        await vm.translatePage(at: 0, bypassCache: true)
        guard case .translated(let bubbles) = vm.pages[0].state else {
            return XCTFail("Expected .translated, got \(vm.pages[0].state)")
        }
        XCTAssertTrue(bubbles.isEmpty, "Punct-only bubbles must not appear in sidebar")
    }

    func testAllMeaninglessBubblesProducesEmptySidebarAndSkipsTranslation() async {
        var translationCalled = false
        let router = await makeRouter(recognizerText: "—")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true })
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/all-meaningless.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]
        await vm.translatePage(at: 0, bypassCache: true)
        // Current code passthroughs punct bubbles into .translated → this assert goes red first
        guard case .translated(let bubbles) = vm.pages[0].state else {
            return XCTFail("Expected .translated, got \(vm.pages[0].state)")
        }
        XCTAssertTrue(bubbles.isEmpty, "All-meaningless page must produce no sidebar entries")
        XCTAssertFalse(translationCalled, "Translation must not be called when all bubbles are meaningless")
    }

    func testMixedBubblesOnlyMeaningfulInSidebar() async {
        // Region 0 → "こんにちは" (meaningful), Region 1 → "。" (punct-only)
        let router = await makeRouterSequential(texts: ["こんにちは", "。"])
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: TrackingTranslationService())
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/mixed.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]
        await vm.translatePage(at: 0, bypassCache: true)
        guard case .translated(let bubbles) = vm.pages[0].state else {
            return XCTFail("Expected .translated, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(bubbles.count, 1)
        XCTAssertEqual(bubbles[0].bubble.text, "こんにちは")
    }

    // MARK: - Sanitized provider API error reaches page state

    func testSanitizedProviderAPIErrorReachesPageStateWithoutRawSensitiveContent() async {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let router = await makeRouter(recognizerText: "こんにちは")
        let sanitized = SanitizedAPIError(
            provider: "OpenAI Compatible",
            statusCode: 401,
            code: "invalid_api_key",
            message: "Invalid API key for project"
        )
        let translationService = QueueingTranslationService(results: [
            .failure(TranslationError.apiError(sanitized))
        ])
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/sanitized-error.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)

        guard case .error(let message) = vm.pages[0].state else {
            return XCTFail("Expected .error after sanitized provider API failure, got \(vm.pages[0].state)")
        }
        XCTAssertTrue(message.contains("OpenAI Compatible"))
        XCTAssertTrue(message.contains("401"))
        XCTAssertTrue(message.contains("invalid_api_key"))
        XCTAssertTrue(message.contains("Invalid API key for project"))
        // Must not leak any token shapes that the sanitizer would normally strip.
        XCTAssertFalse(message.contains("sk-"))
        XCTAssertFalse(message.contains("Bearer "))
        XCTAssertFalse(message.contains("@"))
    }

    // MARK: - Re-translate

    func testRetranslateFailurePreservesPreviousTranslations() async {
        let router = await makeRouter(recognizerText: "こんにちは")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let translationService = QueueingTranslationService(results: [
            .success("你好"),
            .failure(TranslationError.apiError(SanitizedAPIError(
                provider: "Test",
                statusCode: 500,
                code: nil,
                message: "forced retranslate failure"
            )))
        ])
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/retranslate-preserve.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)
        guard case .translated(let firstBubbles) = vm.pages[0].state else {
            return XCTFail("Expected initial translation to succeed, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(firstBubbles.first?.translatedText, "你好")

        await vm.retranslateCurrentPage()

        guard case .translated(let preservedBubbles) = vm.pages[0].state else {
            return XCTFail("Failed re-translate must preserve previous translated state, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(preservedBubbles.first?.translatedText, "你好")
    }

    // MARK: - 3. Cache failure routing (harden-cache-service-error-reporting)

    // 3.1 clearAll failure → no page state changes, no textPixelMask cleared.
    func testViewModelDoesNotResetPagesWhenCacheClearFails() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let mockCache = MockCacheService()
        mockCache.clearAllError = CacheError.unavailable
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: mockCache
        )
        var translatedPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/preserve-1.jpg"))
        translatedPage.state = .translated([
            TranslatedBubble(
                bubble: BubbleCluster(boundingBox: .zero, text: "old", observations: []),
                translatedText: "舊",
                index: 0
            )
        ])
        translatedPage.textPixelMask = makeTestCGImage()
        var errorPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/preserve-2.jpg"))
        errorPage.state = .error("frozen error")
        errorPage.textPixelMask = makeTestCGImage()
        vm.pages = [translatedPage, errorPage]

        vm.clearCacheAndResetPages()

        guard case .translated(let preservedBubbles) = vm.pages[0].state else {
            return XCTFail("Expected page 0 state preserved as .translated, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(preservedBubbles.first?.translatedText, "舊")
        XCTAssertNotNil(vm.pages[0].textPixelMask)
        guard case .error(let preservedMessage) = vm.pages[1].state else {
            return XCTFail("Expected page 1 state preserved as .error, got \(vm.pages[1].state)")
        }
        XCTAssertEqual(preservedMessage, "frozen error")
        XCTAssertNotNil(vm.pages[1].textPixelMask)
    }

    // 3.2 Generic error message set when clearAll fails.
    func testViewModelSetsGenericErrorMessageWhenCacheClearFails() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let mockCache = MockCacheService()
        mockCache.clearAllError = CacheError.unavailable
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: mockCache
        )
        vm.pages = [MangaPage(imageURL: URL(fileURLWithPath: "/tmp/error-message.jpg"))]

        vm.clearCacheAndResetPages()

        XCTAssertEqual(
            vm.errorMessage,
            "Failed to clear cache. Translations may still be cached. Please restart the app if the problem persists."
        )
    }

    // 3.3 SQLite message must NOT leak into errorMessage.
    func testViewModelDoesNotLeakSqliteMessageToErrorMessage() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let mockCache = MockCacheService()
        mockCache.clearAllError = CacheError.sqlite(
            code: 5,
            message: "database is locked",
            operation: "CacheService.clearAll"
        )
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: mockCache
        )
        vm.pages = [MangaPage(imageURL: URL(fileURLWithPath: "/tmp/leak-check.jpg"))]

        vm.clearCacheAndResetPages()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.errorMessage?.contains("database is locked") == true,
                       "errorMessage must not contain raw SQLite text, got: \(vm.errorMessage ?? "nil")")
    }

    // 3.4 SQLite message must be routed to DebugLogger.
    func testViewModelRoutesSqliteMessageToDebugLogger() async {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let mockCache = MockCacheService()
        mockCache.clearAllError = CacheError.sqlite(
            code: 5,
            message: "database is locked",
            operation: "CacheService.clearAll"
        )
        let logFixture = makeDebugLogFixture()
        defer { logFixture.cleanup() }
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: mockCache,
            pipelineLogger: logFixture.logger
        )
        vm.pages = [MangaPage(imageURL: URL(fileURLWithPath: "/tmp/log-route.jpg"))]

        vm.clearCacheAndResetPages()
        await logFixture.logger.flush()

        var filter = DebugLogFilter()
        filter.category = .cache
        filter.sessionIDFilter = .session(logFixture.logger.sessionID)
        let entries = await logFixture.store.queryAll(filter: filter)
        let match = entries.first { entry in
            entry.message.contains("CacheService.clearAll") && entry.message.contains("database is locked")
        }
        XCTAssertNotNil(match, "DebugLogger must record the operation identifier and SQLite text")
    }

    // 3.5 Regression guard: clearAll success still resets pages.
    func testViewModelResetsPagesWhenCacheClearSucceeds() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let mockCache = MockCacheService()
        // No errors configured — clearAll succeeds.
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: mockCache
        )
        var translatedPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/reset-1.jpg"))
        translatedPage.state = .translated([
            TranslatedBubble(
                bubble: BubbleCluster(boundingBox: .zero, text: "old", observations: []),
                translatedText: "舊",
                index: 0
            )
        ])
        translatedPage.textPixelMask = makeTestCGImage()
        var errorPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/reset-2.jpg"))
        errorPage.state = .error("old error")
        errorPage.textPixelMask = makeTestCGImage()
        vm.pages = [translatedPage, errorPage]

        vm.clearCacheAndResetPages()

        for page in vm.pages {
            guard case .pending = page.state else {
                return XCTFail("Expected every page reset to .pending, got \(page.state)")
            }
            XCTAssertNil(page.textPixelMask)
        }
    }

    // 3.6 Translation pipeline continues when store throws.
    func testTranslationPipelineContinuesWhenStoreThrows() async {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let router = await makeRouter(recognizerText: "こんにちは")
        let mockCache = MockCacheService()
        mockCache.storeError = CacheError.sqlite(
            code: 8,
            message: "attempt to write a readonly database",
            operation: "CacheService.store"
        )
        let logFixture = makeDebugLogFixture()
        defer { logFixture.cleanup() }
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: TrackingTranslationService(),
            cacheService: mockCache,
            pipelineLogger: logFixture.logger
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/store-throws.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)
        await logFixture.logger.flush()

        guard case .translated = vm.pages[0].state else {
            return XCTFail("Expected page .translated despite store failure, got \(vm.pages[0].state)")
        }
        var filter = DebugLogFilter()
        filter.category = .cache
        filter.sessionIDFilter = .session(logFixture.logger.sessionID)
        let entries = await logFixture.store.queryAll(filter: filter)
        XCTAssertTrue(
            entries.contains { $0.message.contains("CacheService.store") },
            "DebugLogger must record the store failure"
        )
    }

    // 3.7 Archive-load path continues when addHistory throws.
    func testLoadFilesContinuesWhenAddHistoryThrows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestPNG(at: root.appendingPathComponent("page_1.png"))
        try writeTestPNG(at: root.appendingPathComponent("page_2.png"))

        let mockCache = MockCacheService()
        mockCache.addHistoryError = CacheError.sqlite(
            code: 5,
            message: "database is locked",
            operation: "CacheService.addHistory"
        )
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let router = await makeSingleRegionRouterSequential(texts: ["page"])
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: TrackingTranslationService(),
            cacheService: mockCache
        )

        await vm.loadFolder(root)

        XCTAssertEqual(vm.pages.count, 2)
        XCTAssertNil(vm.errorMessage, "addHistory failure must not present an alert")
    }

    // MARK: - Cache management

    func testClearCacheAndResetPagesMarksLoadedPagesPendingWithoutRetranslating() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let translationService = TrackingTranslationService()
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: translationService)
        var translatedPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/page-1.jpg"))
        translatedPage.state = .translated([
            TranslatedBubble(
                bubble: BubbleCluster(boundingBox: .zero, text: "old", observations: []),
                translatedText: "舊",
                index: 0
            )
        ])
        translatedPage.textPixelMask = makeTestCGImage()
        var errorPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/page-2.jpg"))
        errorPage.state = .error("old error")
        errorPage.textPixelMask = makeTestCGImage()
        vm.pages = [translatedPage, errorPage]

        vm.clearCacheAndResetPages()

        for page in vm.pages {
            guard case .pending = page.state else {
                return XCTFail("Expected every loaded page to reset to pending, got \(page.state)")
            }
            XCTAssertNil(page.textPixelMask)
        }
    }

    // MARK: - Glossary and contextual translation

    func testActiveGlossaryTermsArePassedToTranslationContext() async {
        let router = await makeRouter(recognizerText: "太郎")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let translationService = CapturingTranslationService()
        let cache = makeTempCache()
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService, cacheService: cache)
        let glossary = try? vm.glossaryServiceForView.createGlossary(name: "Names")
        XCTAssertNotNil(glossary)
        _ = try? vm.glossaryServiceForView.addTerm(
            glossaryID: glossary!.id,
            sourceTerm: "太郎",
            targetTerm: "太郎",
            autoDetected: false
        )
        vm.loadGlossaries()
        vm.activeGlossaryID = glossary?.id
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/glossary-context.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)

        XCTAssertEqual(translationService.contexts.last?.glossaryTerms.first?.sourceTerm, "太郎")
        XCTAssertEqual(translationService.contexts.last?.glossaryTerms.first?.targetTerm, "太郎")
    }

    func testRecentTranslationContextKeepsOnlyPreviousThreePages() async {
        let router = await makeSingleRegionRouterSequential(texts: ["p1", "p2", "p3", "p4"])
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let translationService = CapturingTranslationService()
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
        vm.pages = (0..<4).map { index in
            var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/context-\(index).jpg"))
            page.image = makeTestImage()
            return page
        }

        for index in 0..<4 {
            await vm.translatePage(at: index, bypassCache: true)
        }

        XCTAssertEqual(translationService.contexts.count, 4)
        XCTAssertEqual(translationService.contexts[0].recentPageSummaries, [])
        XCTAssertEqual(translationService.contexts[3].recentPageSummaries, ["T:p1", "T:p2", "T:p3"])
    }

    // MARK: - File input and batch navigation

    func testScanFolderFindsNestedImagesInNaturalFilenameOrderAndSkipsMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("chapter")
        let metadata = root.appendingPathComponent("__MACOSX")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let page10 = root.appendingPathComponent("page_10.jpg")
        let page2 = root.appendingPathComponent("page_2.jpg")
        let page1 = nested.appendingPathComponent("page_1.png")
        let ignored = metadata.appendingPathComponent("page_0.jpg")
        let note = root.appendingPathComponent("notes.txt")
        for url in [page10, page2, page1, ignored, note] {
            try Data("x".utf8).write(to: url)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = FileInputService.scanFolder(root).map(\.lastPathComponent)

        XCTAssertEqual(scanned, ["page_1.png", "page_2.jpg", "page_10.jpg"])
    }

    func testPageNavigationClampsAtCollectionBoundsAndClearsHighlight() {
        let vm = TranslationViewModel(preferences: makePrefs(source: .ja, target: .zhHant))
        vm.pages = [
            MangaPage(imageURL: URL(fileURLWithPath: "/tmp/nav-1.jpg")),
            MangaPage(imageURL: URL(fileURLWithPath: "/tmp/nav-2.jpg"))
        ]
        vm.highlightedBubbleId = UUID()

        vm.nextPage()
        XCTAssertEqual(vm.currentPageIndex, 1)
        XCTAssertNil(vm.highlightedBubbleId)

        vm.nextPage()
        XCTAssertEqual(vm.currentPageIndex, 1)

        vm.highlightedBubbleId = UUID()
        vm.previousPage()
        XCTAssertEqual(vm.currentPageIndex, 0)
        XCTAssertNil(vm.highlightedBubbleId)

        vm.previousPage()
        XCTAssertEqual(vm.currentPageIndex, 0)
    }

    func testLoadFolderTranslatesNoMoreThanThreePagesConcurrently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 1...6 {
            try writeTestPNG(at: root.appendingPathComponent("page_\(index).png"))
        }

        let router = await makeSingleRegionRouterSequential(texts: ["page"])
        let translationService = ConcurrencyTrackingTranslationService(delay: 50_000_000)
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: translationService
        )

        await vm.loadFolder(root)

        XCTAssertEqual(vm.pages.count, 6)
        let maxConcurrent = await translationService.maxConcurrent()
        XCTAssertLessThanOrEqual(maxConcurrent, 3)
    }

    func testLoadArchiveUsesOriginalSourcePathAndLoadsExtractedImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestPNG(at: root.appendingPathComponent("page_2.png"))
        try writeTestPNG(at: root.appendingPathComponent("page_1.png"))
        let archive = try makeZipArchive(from: root)
        defer { try? FileManager.default.removeItem(at: archive) }

        let router = await makeSingleRegionRouterSequential(texts: ["page"])
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: TrackingTranslationService()
        )

        await vm.loadArchive(archive)

        XCTAssertEqual(vm.sourcePath, archive.path)
        XCTAssertEqual(vm.pages.map { $0.imageURL.lastPathComponent }, ["page_1.png", "page_2.png"])
    }

    func testLoadArchiveFailureSetsErrorWithoutDroppingExistingPages() async {
        let vm = TranslationViewModel(preferences: makePrefs(source: .ja, target: .zhHant))
        vm.pages = [MangaPage(imageURL: URL(fileURLWithPath: "/tmp/existing.png"))]

        await vm.loadArchive(URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).cbz"))

        XCTAssertEqual(vm.pages.count, 1)
        XCTAssertTrue(vm.errorMessage?.contains("Failed to extract archive") == true)
    }

    // MARK: - Batch recent-context ordering (fix-batch-recent-context-order)

    func testLLMBatchTranslationBuildsRecentContextInPageOrder() async throws {
        // Six pages span two LLM batches (maxPages=5). The within-batch priorContext is
        // sampled once at the batch boundary; pages internal to a batch share that context.
        let widths = [111, 112, 113, 114, 115, 116]
        let texts = ["p1", "p2", "p3", "p4", "p5", "p6"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        let (root, recognizer, translationService, vm) = try await makeBatchOrderingFixture(
            widths: widths,
            textByWidth: textByWidth,
            engine: .githubCopilot,
            delaysByInput: ["p1": 50_000_000, "p2": 250_000_000]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        _ = recognizer

        await vm.loadFolder(root)

        XCTAssertEqual(translationService.callCount, 6)
        // Batch 1 (pages 1..5): priorContext is empty (no successful page with index < 1).
        // The default TranslationService.translateBatch extension delegates to per-page
        // translate(...) so each recorded call observes the same batch-level priorContext.
        for text in ["p1", "p2", "p3", "p4", "p5"] {
            XCTAssertEqual(
                translationService.context(forInput: text)?.recentPageSummaries,
                [],
                "Within-batch pages share the batch-level priorContext (\(text))"
            )
        }
        // Batch 2 (page 6): rolling window after batch 1 finalized is trimmed to last 3.
        XCTAssertEqual(
            translationService.context(forInput: "p6")?.recentPageSummaries,
            ["T:p3", "T:p4", "T:p5"]
        )
    }

    func testNonContextualEnginesDoNotReceiveRecentPageContext() async throws {
        let widths = [121, 122, 123, 124]
        let texts = ["q1", "q2", "q3", "q4"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        let (root, recognizer, translationService, vm) = try await makeBatchOrderingFixture(
            widths: widths,
            textByWidth: textByWidth,
            engine: .deepL
        )
        defer { try? FileManager.default.removeItem(at: root) }
        _ = recognizer

        let glossary = try? vm.glossaryServiceForView.createGlossary(name: "BatchNonLLM")
        XCTAssertNotNil(glossary)
        _ = try? vm.glossaryServiceForView.addTerm(
            glossaryID: glossary!.id,
            sourceTerm: "q1",
            targetTerm: "Q1",
            autoDetected: false
        )
        vm.loadGlossaries()
        vm.activeGlossaryID = glossary?.id

        await vm.loadFolder(root)

        XCTAssertEqual(translationService.callCount, 4)
        for input in texts {
            let ctx = translationService.context(forInput: input)
            XCTAssertNotNil(ctx, "Missing context for \(input)")
            XCTAssertEqual(ctx?.recentPageSummaries, [], "DeepL/Google must receive empty recentPageSummaries for \(input)")
            XCTAssertEqual(ctx?.glossaryTerms.first?.sourceTerm, "q1", "Glossary must still flow for \(input)")
            XCTAssertEqual(ctx?.glossaryTerms.first?.targetTerm, "Q1", "Glossary must still flow for \(input)")
        }
    }

    func testOcrWorkCanStillCompleteBeforeSerialLLMTranslation() async throws {
        let widths = [131, 132, 133, 134, 135, 136]
        let texts = ["r1", "r2", "r3", "r4", "r5", "r6"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        let delays = Dictionary(uniqueKeysWithValues: texts.map { ($0, UInt64(120_000_000)) })
        let (root, recognizer, translationService, vm) = try await makeBatchOrderingFixture(
            widths: widths,
            textByWidth: textByWidth,
            engine: .githubCopilot,
            delaysByInput: delays
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(translationService.callOrderInputs, texts,
                       "LLM translation calls must start in ascending page-index order")
        XCTAssertEqual(translationService.maxConcurrentTranslations, 1,
                       "Context-consuming LLM engines must not run concurrently")
        XCTAssertEqual(
            translationService.ocrCountAtFirstTranslate,
            widths.count,
            "OCR must complete for all pages before the first LLM translation starts"
        )
        XCTAssertEqual(recognizer.observedTextsInOrder.count, widths.count)
    }

    func testLLMBatchCacheHitsContributeToLaterRecentContextWithoutRetranslating() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let widths = [141, 142]
        let texts = ["s1", "s2"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        try writeUniqueColoredPNG(at: root.appendingPathComponent("page_1.png"), width: widths[0])

        let recognizer = SizeMappedOCRRecognizer(textByWidth: textByWidth)
        let translationService = OrderedContextRecorder(engine: .githubCopilot, ocrObserver: recognizer)
        let router = await makeOrderedBatchRouter(recognizer: recognizer)
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: translationService
        )
        vm.clearCacheAndResetPages()

        // First load populates the translation cache for page_1.
        await vm.loadFolder(root)
        XCTAssertEqual(translationService.callOrderInputs, ["s1"],
                       "First batch must translate page 1")
        guard case .translated = vm.pages[0].state else {
            return XCTFail("Expected page 1 to be .translated after first batch, got \(vm.pages[0].state)")
        }

        // Add page_2 then re-load: page_1 should be a cache hit, page_2 should translate.
        try writeUniqueColoredPNG(at: root.appendingPathComponent("page_2.png"), width: widths[1])
        await vm.loadFolder(root)

        XCTAssertEqual(vm.pages.count, 2)
        XCTAssertEqual(translationService.callOrderInputs, ["s1", "s2"],
                       "Second batch must translate page 2 only; page 1 must be served from cache")
        let s2Ctx = translationService.context(forInput: "s2")
        XCTAssertEqual(
            s2Ctx?.recentPageSummaries,
            ["T:s1"],
            "Cache-hit page must contribute its cached translated text to later LLM recent context"
        )
    }

    func testLLMBatchSkipsFailedPagesInLaterRecentContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let widths = [151, 152]
        let texts = ["t1", "t2"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        for (i, width) in widths.enumerated() {
            try writeUniqueColoredPNG(at: root.appendingPathComponent("page_\(i + 1).png"), width: width)
        }

        let recognizer = SizeMappedOCRRecognizer(textByWidth: textByWidth, throwForWidths: [widths[0]])
        let translationService = OrderedContextRecorder(engine: .githubCopilot, ocrObserver: recognizer)
        let router = await makeOrderedBatchRouter(recognizer: recognizer)
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: translationService
        )
        vm.clearCacheAndResetPages()

        await vm.loadFolder(root)

        guard case .error = vm.pages[0].state else {
            return XCTFail("Expected page 1 to be .error after OCR failure, got \(vm.pages[0].state)")
        }
        guard case .translated = vm.pages[1].state else {
            return XCTFail("Expected page 2 to be .translated despite page 1 failing, got \(vm.pages[1].state)")
        }
        XCTAssertEqual(translationService.callOrderInputs, ["t2"],
                       "Failed page must not call the translation service")
        XCTAssertEqual(
            translationService.context(forInput: "t2")?.recentPageSummaries,
            [],
            "Failed page must not contribute to later recent-page context"
        )
    }

    func testRetranslateAllPagesUsesPageOrderedRecentContextForLLMEngines() async throws {
        // Six pages so retranslate-all spans two batches and exercises the batch-level
        // priorContext rule (Decision 2) for both the initial load and the retranslate.
        let widths = [161, 162, 163, 164, 165, 166]
        let texts = ["u1", "u2", "u3", "u4", "u5", "u6"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        let (root, _, translationService, vm) = try await makeBatchOrderingFixture(
            widths: widths,
            textByWidth: textByWidth,
            engine: .githubCopilot,
            delaysByInput: ["u2": 200_000_000]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Initial load to populate pages and cache.
        await vm.loadFolder(root)
        XCTAssertEqual(translationService.callCount, 6)

        // Retranslate all pages bypasses cache and applies the same per-batch context rules.
        await vm.retranslateAllPages()

        XCTAssertEqual(translationService.callCount, 12)
        let retranslate = translationService.contextsForRetranslateBatch(inputs: texts)
        // Batch 1 (u1..u5): all share an empty priorContext.
        for text in ["u1", "u2", "u3", "u4", "u5"] {
            XCTAssertEqual(retranslate[text], [], "Within-batch \(text)")
        }
        // Batch 2 (u6): priorContext is the rolling window after batch 1 trimmed to last 3.
        XCTAssertEqual(retranslate["u6"], ["T:u3", "T:u4", "T:u5"])
    }
}

// MARK: - Helpers

private func makeTestCGImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 10, space: colorSpace, bitmapInfo: 0)!
    return context.makeImage()!
}

private func makeTestImage() -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 100,
        pixelsHigh: 100,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 100 * 4,
        bitsPerPixel: 32
    )!
    let image = NSImage(size: NSSize(width: 100, height: 100))
    image.addRepresentation(rep)
    return image
}

private func writeTestPNG(at url: URL, width: Int = 16, height: Int = 16) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw OCRError.invalidImage
    }
    try data.write(to: url)
}

private func makeZipArchive(from directory: URL) throws -> URL {
    let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    task.arguments = ["-q", "-r", archive.path, "."]
    task.currentDirectoryURL = directory
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
        throw FileInputError.extractionFailed
    }
    return archive
}

@MainActor
private func makeEmptyRouter() -> OCRRouter {
    return OCRRouter(
        mangaOCRService: MangaOCRService(detector: EmptyComicTextDetector()),
        capabilityChecker: MockCapabilityChecker(.unsupported),
        downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
        paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
    )
}

private func decodeMeta(_ json: String) -> [String: String] {
    guard let data = json.data(using: .utf8),
          let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return dict
}

private func makeDebugLogFixture() -> (store: DebugLogStore, logger: DebugLogger, cleanup: () -> Void) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    let store = DebugLogStore(databaseURL: url)
    let logger = DebugLogger(store: store)
    return (store, logger, { try? FileManager.default.removeItem(at: url) })
}

@MainActor
private func makeRouter(recognizerText: String) async -> OCRRouter {
    let recognizer = FixedTextOCRRecognizer(text: recognizerText)
    let service = MangaOCRService(detector: MockComicTextDetectorSingle())
    await service.setRecognizer(recognizer)
    return OCRRouter(
        mangaOCRService: service,
        capabilityChecker: MockCapabilityChecker(.unsupported),
        downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
        paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
    )
}

@MainActor
private func makeRouterSequential(texts: [String]) async -> OCRRouter {
    let recognizer = SequentialOCRRecognizer(texts: texts)
    let service = MangaOCRService(detector: MockComicTextDetectorDouble())
    await service.setRecognizer(recognizer)
    return OCRRouter(
        mangaOCRService: service,
        capabilityChecker: MockCapabilityChecker(.unsupported),
        downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
        paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
    )
}

@MainActor
private func makeSingleRegionRouterSequential(texts: [String]) async -> OCRRouter {
    let recognizer = SequentialOCRRecognizer(texts: texts)
    let service = MangaOCRService(detector: MockComicTextDetectorSingle())
    await service.setRecognizer(recognizer)
    return OCRRouter(
        mangaOCRService: service,
        capabilityChecker: MockCapabilityChecker(.unsupported),
        downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
        paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
    )
}

private func makePrefs(source: Language, target: Language) -> PreferencesService {
    let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    prefs.sourceLanguage = source
    prefs.targetLanguage = target
    return prefs
}

// MARK: - Mock Types

private final class ThrowingOCRRecognizer: OCRRecognizing {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        throw PaddleOCRError.inferenceFailed("forced")
    }
}

private final class FixedTextOCRRecognizer: OCRRecognizing {
    private let text: String
    init(text: String) { self.text = text }
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        return (text, 1.0)
    }
}

private final class SequentialOCRRecognizer: @unchecked Sendable, OCRRecognizing {
    private let texts: [String]
    private var callCount = 0
    init(texts: [String]) { self.texts = texts }
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        let text = texts[callCount % texts.count]
        callCount += 1
        return (text, 1.0)
    }
}

private struct EmptyComicTextDetector: ComicTextDetecting {
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        ComicTextDetectorResult(regions: [], textPixelMask: nil, lowConfidenceRegionCount: 0)
    }
}

private struct MockComicTextDetectorSingle: ComicTextDetecting {
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        ComicTextDetectorResult(
            regions: [DetectedTextRegion(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), confidence: 1.0, classIndex: 0)],
            textPixelMask: nil,
            lowConfidenceRegionCount: 0
        )
    }
}

private struct MockComicTextDetectorDouble: ComicTextDetecting {
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        ComicTextDetectorResult(
            regions: [
                DetectedTextRegion(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), confidence: 1.0, classIndex: 0),
                DetectedTextRegion(boundingBox: CGRect(x: 20, y: 20, width: 10, height: 10), confidence: 1.0, classIndex: 0)
            ],
            textPixelMask: nil,
            lowConfidenceRegionCount: 0
        )
    }
}

private final class TrackingTranslationService: TranslationService {
    var engine: TranslationEngine { .githubCopilot }
    private let onTranslate: (() -> Void)?
    init(onTranslate: (() -> Void)? = nil) { self.onTranslate = onTranslate }
    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        onTranslate?()
        let translated = bubbles.map { TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index) }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }
}

private final class QueueingTranslationService: TranslationService {
    var engine: TranslationEngine { .githubCopilot }
    private var results: [Result<String, Error>]

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        let result = results.isEmpty ? .success("translated") : results.removeFirst()
        let translatedText = try result.get()
        let translated = bubbles.map {
            TranslatedBubble(bubble: $0, translatedText: translatedText, index: $0.index)
        }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }
}

private final class CapturingTranslationService: TranslationService {
    var engine: TranslationEngine { .githubCopilot }
    private(set) var contexts: [TranslationContext] = []

    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        contexts.append(context)
        let translated = bubbles.map {
            TranslatedBubble(bubble: $0, translatedText: "T:\($0.text)", index: $0.index)
        }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }
}

private final class ConcurrencyTrackingTranslationService: TranslationService {
    var engine: TranslationEngine { .githubCopilot }
    private let delay: UInt64
    private let counter = ConcurrencyCounter()

    init(delay: UInt64) {
        self.delay = delay
    }

    func maxConcurrent() async -> Int {
        await counter.maxConcurrent
    }

    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        await counter.enter()

        try await Task.sleep(nanoseconds: delay)

        await counter.leave()

        let translated = bubbles.map {
            TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index)
        }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }
}

private actor ConcurrencyCounter {
    private var current = 0
    private(set) var maxConcurrent = 0

    func enter() {
        current += 1
        maxConcurrent = max(maxConcurrent, current)
    }

    func leave() {
        current -= 1
    }
}

// CacheServiceProtocol double used by 3.x tests. Each mutation may be
// configured to throw a specific CacheError; reads always degrade.
private final class MockCacheService: CacheServiceProtocol {
    var isAvailable: Bool = true
    var storeError: Error?
    var addHistoryError: Error?
    var clearAllError: Error?
    private(set) var storeCallCount = 0
    private(set) var addHistoryCallCount = 0
    private(set) var clearAllCallCount = 0
    let glossaryService: GlossaryService

    init() {
        // No backing database; glossary reads/writes degrade naturally.
        self.glossaryService = GlossaryService(db: nil, isAvailable: false)
    }

    func lookup(
        imageHash: String, source: Language, target: Language, engine: TranslationEngine
    ) -> CacheService.CachedTranslationResult? {
        return nil
    }

    func translationCacheSize() -> Int64 { 0 }

    func store(
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine,
        bubbles: [TranslatedBubble],
        textPixelMask: CGImage?
    ) throws {
        storeCallCount += 1
        if let storeError { throw storeError }
    }

    func addHistory(path: String, pageCount: Int?) throws {
        addHistoryCallCount += 1
        if let addHistoryError { throw addHistoryError }
    }

    func clearAll() throws {
        clearAllCallCount += 1
        if let clearAllError { throw clearAllError }
    }
}

private final class MockCapabilityChecker: DeviceCapabilityChecking {
    private let capability: PaddleOCRCapability
    init(_ capability: PaddleOCRCapability) { self.capability = capability }
    func checkPaddleOCRCapability() -> PaddleOCRCapability { capability }
}

private final class MockDownloadManager: ModelDownloadManaging {
    let state: ModelDownloadState
    private let enabled: Bool
    init(state: ModelDownloadState, enabled: Bool = false) {
        self.state = state
        self.enabled = enabled
    }
    var isPaddleOCREnabled: Bool { state == .downloaded && enabled }
}

// MARK: - Batch ordering helpers (fix-batch-recent-context-order)

// Writes a PNG with a unique fill color so the cache image hash differs across test invocations.
private func writeUniqueColoredPNG(at url: URL, width: Int = 16, height: Int = 16) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = CGFloat.random(in: 0...1)
    let g = CGFloat.random(in: 0...1)
    let b = CGFloat.random(in: 0...1)
    NSColor(red: r, green: g, blue: b, alpha: 1.0).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw OCRError.invalidImage
    }
    try data.write(to: url)
}

// OCR recognizer that maps the page image's CGImage.width to a fixed text and can throw for chosen widths.
private final class SizeMappedOCRRecognizer: @unchecked Sendable, OCRRecognizing {
    private let textByWidth: [Int: String]
    private let throwForWidths: Set<Int>
    private let lock = NSLock()
    private var _observedTextsInOrder: [String] = []

    init(textByWidth: [Int: String], throwForWidths: Set<Int> = []) {
        self.textByWidth = textByWidth
        self.throwForWidths = throwForWidths
    }

    var observedTextsInOrder: [String] {
        lock.lock(); defer { lock.unlock() }
        return _observedTextsInOrder
    }

    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        let width = cgImage.width
        if throwForWidths.contains(width) {
            throw PaddleOCRError.inferenceFailed("forced for width \(width)")
        }
        let text = textByWidth[width] ?? ""
        lock.lock()
        _observedTextsInOrder.append(text)
        lock.unlock()
        return (text, 1.0)
    }
}

// Translation service that records each call's input and context, tracks call order and concurrency,
// and snapshots the OCR call count when the first translation begins.
private final class OrderedContextRecorder: @unchecked Sendable, TranslationService {
    private let recordedEngine: TranslationEngine
    var engine: TranslationEngine { recordedEngine }

    private let lock = NSLock()
    private var _calls: [(input: String, context: TranslationContext)] = []
    private var _callOrderInputs: [String] = []
    private var _maxConcurrent: Int = 0
    private var _currentConcurrent: Int = 0
    private var _ocrCountAtFirstTranslate: Int?

    private let delaysByInput: [String: UInt64]
    private let failingInputs: Set<String>
    private weak var ocrObserver: SizeMappedOCRRecognizer?

    init(engine: TranslationEngine = .githubCopilot,
         delaysByInput: [String: UInt64] = [:],
         failingInputs: Set<String> = [],
         ocrObserver: SizeMappedOCRRecognizer? = nil) {
        self.recordedEngine = engine
        self.delaysByInput = delaysByInput
        self.failingInputs = failingInputs
        self.ocrObserver = ocrObserver
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _calls.count
    }

    var callOrderInputs: [String] {
        lock.lock(); defer { lock.unlock() }
        return _callOrderInputs
    }

    var maxConcurrentTranslations: Int {
        lock.lock(); defer { lock.unlock() }
        return _maxConcurrent
    }

    var ocrCountAtFirstTranslate: Int? {
        lock.lock(); defer { lock.unlock() }
        return _ocrCountAtFirstTranslate
    }

    func context(forInput input: String) -> TranslationContext? {
        lock.lock(); defer { lock.unlock() }
        return _calls.first { $0.input == input }?.context
    }

    // For retranslate-all tests, the second pass through the same inputs is the last N calls
    // (where N == inputs.count). Return a map from input to its recentPageSummaries.
    func contextsForRetranslateBatch(inputs: [String]) -> [String: [String]] {
        lock.lock(); defer { lock.unlock() }
        let tail = _calls.suffix(inputs.count)
        var result: [String: [String]] = [:]
        for call in tail {
            result[call.input] = call.context.recentPageSummaries
        }
        return result
    }

    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        let inputText = bubbles.first?.text ?? ""
        let observerCount = ocrObserver?.observedTextsInOrder.count

        lock.withLock {
            if _ocrCountAtFirstTranslate == nil {
                _ocrCountAtFirstTranslate = observerCount
            }
            _callOrderInputs.append(inputText)
            _calls.append((input: inputText, context: context))
            _currentConcurrent += 1
            if _currentConcurrent > _maxConcurrent {
                _maxConcurrent = _currentConcurrent
            }
        }

        defer {
            lock.withLock { _currentConcurrent -= 1 }
        }

        if failingInputs.contains(inputText) {
            throw TranslationError.apiError(SanitizedAPIError(
                provider: "Test",
                statusCode: 500,
                code: nil,
                message: "forced failure for \(inputText)"
            ))
        }

        if let delay = delaysByInput[inputText], delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }

        let translated = bubbles.map {
            TranslatedBubble(bubble: $0, translatedText: "T:\($0.text)", index: $0.index)
        }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }
}

@MainActor
private func makeOrderedBatchRouter(recognizer: SizeMappedOCRRecognizer) async -> OCRRouter {
    let service = MangaOCRService(detector: MockComicTextDetectorSingle())
    await service.setRecognizer(recognizer)
    return OCRRouter(
        mangaOCRService: service,
        capabilityChecker: MockCapabilityChecker(.unsupported),
        downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
        paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
    )
}

@MainActor
private func makeBatchOrderingFixture(
    widths: [Int],
    textByWidth: [Int: String],
    engine: TranslationEngine,
    delaysByInput: [String: UInt64] = [:],
    failingInputs: Set<String> = []
) async throws -> (root: URL, recognizer: SizeMappedOCRRecognizer, translationService: OrderedContextRecorder, viewModel: TranslationViewModel) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (i, width) in widths.enumerated() {
        try writeUniqueColoredPNG(at: root.appendingPathComponent("page_\(i + 1).png"), width: width)
    }

    let recognizer = SizeMappedOCRRecognizer(textByWidth: textByWidth)
    let translationService = OrderedContextRecorder(
        engine: engine,
        delaysByInput: delaysByInput,
        failingInputs: failingInputs,
        ocrObserver: recognizer
    )
    let router = await makeOrderedBatchRouter(recognizer: recognizer)
    let vm = TranslationViewModel(
        preferences: makePrefs(source: .ja, target: .zhHant),
        ocrRouter: router,
        translationService: translationService,
        cacheService: makeTempCache()
    )
    vm.clearCacheAndResetPages()
    return (root, recognizer, translationService, vm)
}

private func makeTempCache() -> CacheService {
    CacheService(databasePath: NSTemporaryDirectory() + "vm-test-\(UUID().uuidString).sqlite")
}

// MARK: - Batch scheduler test infrastructure (batch-llm-translation-pipeline)

// Detector that emits a configurable number of regions per page, keyed by image width.
// The page image must be created with a distinct width per page so each page can declare
// its own bubble count.
private struct FixedRegionCountDetector: ComicTextDetecting {
    let countByWidth: [Int: Int]
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        let count = countByWidth[cgImage.width] ?? 0
        let regions: [DetectedTextRegion] = (0..<count).map { i in
            DetectedTextRegion(
                boundingBox: CGRect(x: 10, y: i * 12, width: 20, height: 12),
                confidence: 1.0,
                classIndex: 0
            )
        }
        return ComicTextDetectorResult(regions: regions, textPixelMask: nil, lowConfidenceRegionCount: 0)
    }
}

// Returns a unique non-empty text per region so the meaningful-bubble filter never drops it.
private final class UniqueTextRecognizer: @unchecked Sendable, OCRRecognizing {
    private let lock = NSLock()
    private var counters: [Int: Int] = [:]
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        let width = cgImage.width
        let idx: Int = lock.withLock {
            let next = counters[width, default: 0]
            counters[width] = next + 1
            return next
        }
        return ("w\(width)b\(idx)", 1.0)
    }
}

// Records every translateBatch and translate(...) invocation for assertions and supports
// failure injection (failBatchForPageIds) and a cancel-aware suspension (suspendUntilCancel).
private final class RecordingBatchTranslationService: @unchecked Sendable, TranslationService {
    private let engineKind: TranslationEngine
    var engine: TranslationEngine { engineKind }

    private let lock = NSLock()
    private var _batchCalls: [(pageIds: [String], summaries: [String])] = []
    private var _perPageCalls: [(input: String, summaries: [String])] = []
    var failBatchForPageIds: Set<String> = []
    var suspendBatchUntilCancel: Bool = false
    // Optional hook fired after translateBatch has produced outputs but before returning.
    // Used to simulate cancellation that arrives between the API completing and the
    // view-model persisting the batch outputs.
    var onBatchSuccessBeforeReturn: (@Sendable () async -> Void)?

    init(engine: TranslationEngine = .githubCopilot) {
        self.engineKind = engine
    }

    var batchCalls: [(pageIds: [String], summaries: [String])] {
        lock.lock(); defer { lock.unlock() }
        return _batchCalls
    }
    var perPageCalls: [(input: String, summaries: [String])] {
        lock.lock(); defer { lock.unlock() }
        return _perPageCalls
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        let input = bubbles.first?.text ?? ""
        lock.withLock { _perPageCalls.append((input: input, summaries: context.recentPageSummaries)) }
        let translated = bubbles.map {
            TranslatedBubble(bubble: $0, translatedText: "T:\($0.text)", index: $0.index)
        }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        let pageIds = pageInputs.map { $0.pageId }
        lock.withLock { _batchCalls.append((pageIds: pageIds, summaries: priorContext.recentPageSummaries)) }

        if suspendBatchUntilCancel {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            throw CancellationError()
        }

        if !failBatchForPageIds.isDisjoint(with: Set(pageIds)) {
            throw TranslationError.apiError(SanitizedAPIError(
                provider: "Test", statusCode: 500, code: nil, message: "forced batch failure"
            ))
        }

        let outputs = pageInputs.map { input in
            let translated = input.bubbles.map {
                TranslatedBubble(bubble: $0, translatedText: "T:\($0.text)", index: $0.index)
            }
            return BatchPageOutput(pageId: input.pageId, bubbles: translated, detectedTerms: [])
        }
        if let hook = onBatchSuccessBeforeReturn {
            await hook()
        }
        return outputs
    }
}

// Sendable holder so a translateBatch hook can cancel the outer Task that owns it.
private final class TaskHandleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?
    func set(_ t: Task<Void, Never>) { lock.withLock { _task = t } }
    func cancel() { (lock.withLock { _task })?.cancel() }
}

@MainActor
private func makeBatchSchedulerFixture(
    bubbleCountsByPage: [Int],
    engine: TranslationEngine = .githubCopilot
) async throws -> (root: URL, service: RecordingBatchTranslationService, vm: TranslationViewModel, cache: CacheService) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    var countByWidth: [Int: Int] = [:]
    for (i, count) in bubbleCountsByPage.enumerated() {
        let width = 300 + i
        countByWidth[width] = count
        try writeUniqueColoredPNG(at: root.appendingPathComponent("page_\(i + 1).png"), width: width)
    }

    let detector = FixedRegionCountDetector(countByWidth: countByWidth)
    let mocService = MangaOCRService(detector: detector)
    await mocService.setRecognizer(UniqueTextRecognizer())
    let router = OCRRouter(
        mangaOCRService: mocService,
        capabilityChecker: MockCapabilityChecker(.unsupported),
        downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
        paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
    )
    let translationService = RecordingBatchTranslationService(engine: engine)
    let cache = makeTempCache()
    let prefs = makePrefs(source: .ja, target: .zhHant)
    // Align preferences.translationEngine with the fake service's engine so cache
    // lookups (keyed by preferences.translationEngine) match what tests store.
    prefs.translationEngine = engine
    let vm = TranslationViewModel(
        preferences: prefs,
        ocrRouter: router,
        translationService: translationService,
        cacheService: cache
    )
    vm.clearCacheAndResetPages()
    return (root, translationService, vm, cache)
}

// MARK: - Batch scheduler tests

@MainActor
final class BatchSchedulerTests: XCTestCase {

    // 6.1
    func testRunBatchPipelineGroupsFiveLowBubblePagesIntoOneBatch() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [8, 8, 8, 8, 8]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 1)
        XCTAssertEqual(service.batchCalls.first?.pageIds, ["0", "1", "2", "3", "4"])
        XCTAssertEqual(service.perPageCalls.count, 0)
    }

    // 6.2 (spec-aligned: [20, 20, 20, 5, 5] yields [0,1] then [2,3,4])
    func testRunBatchPipelineFlushesOnBubbleThreshold() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [20, 20, 20, 5, 5]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 2)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0", "1"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["2", "3", "4"])
    }

    // 6.3
    func testRunBatchPipelineFlushesOnPageCap() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4, 4, 4, 4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 2)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0", "1", "2", "3", "4"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["5", "6", "7"])
    }

    // 6.4
    func testRunBatchPipelineSinglePageOverBubbleThresholdRunsAlone() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [60, 10]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 2)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1"])
    }

    // 6.5
    func testRunBatchPipelineCacheHitActsAsBatchBoundary() async throws {
        let (root, service, vm, cache) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Pre-populate cache for page_3.png so its preparation is `.cacheHit` and flushes batch [0,1].
        let page3URL = root.appendingPathComponent("page_3.png")
        let data = try Data(contentsOf: page3URL)
        let hash = CacheService.imageHash(data: data)
        let cachedBubble = TranslatedBubble(
            bubble: BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "cached-src", observations: []),
            translatedText: "cached-T",
            index: 0
        )
        try cache.store(
            imageHash: hash,
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [cachedBubble],
            textPixelMask: nil
        )

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 2)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0", "1"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["3", "4"])
        XCTAssertFalse(service.batchCalls.contains { $0.pageIds.contains("2") })
    }

    // 6.6
    func testRunBatchPipelineCachedPageContributesToNextBatchRecentContext() async throws {
        let (root, service, vm, cache) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let page3URL = root.appendingPathComponent("page_3.png")
        let data = try Data(contentsOf: page3URL)
        let hash = CacheService.imageHash(data: data)
        let cachedBubble = TranslatedBubble(
            bubble: BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "cached-src", observations: []),
            translatedText: "cached-text",
            index: 0
        )
        try cache.store(
            imageHash: hash,
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [cachedBubble],
            textPixelMask: nil
        )

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 2)
        // Batch 2's priorContext contains pages with index < 4 (its first page).
        // After batch 1 (pages 0, 1) and the cache hit (page 2), the rolling window has
        // batch1-page0, batch1-page1, page2's cached text.
        let secondBatchSummaries = service.batchCalls[1].summaries
        XCTAssertTrue(
            secondBatchSummaries.contains(where: { $0.contains("cached-text") }),
            "Second batch's priorContext must contain page 2's cached translated text — got \(secondBatchSummaries)"
        )
    }

    // 6.7
    func testRunBatchPipelineBatchFailureFallsBackToPerPageInPageIndexOrder() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 20, 20, 5]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // 4 + 4 + 20 = 28 ≤ 45 and 4 pages ≤ 5, but adding page 3 (20) → 48 > 45 so flush.
        // With [4,4,20,20,5]: group [0,1,2]=28, +page 3 (20) → 48 overflow → flush.
        //   Then [3]=20, +4 (5)=25 ≤ 45, group [3,4].
        // We want the second group's batch call to fail.
        service.failBatchForPageIds = ["3", "4"]

        await vm.loadFolder(root)

        // The fallback path uses the per-page translate(...) for each page in the failed group.
        let perPageInputs = service.perPageCalls.map { $0.input }
        XCTAssertEqual(perPageInputs.count, 2, "Pages 3 and 4 must fall back to per-page (got \(perPageInputs))")
        // Page-index order: page 3's bubble comes first, then page 4's.
        // Bubble text is "w<width>b<idx>"; widths are 303 for page 3 and 304 for page 4.
        XCTAssertTrue(perPageInputs[0].hasPrefix("w303"), "First per-page call must be for page 3 (got \(perPageInputs[0]))")
        XCTAssertTrue(perPageInputs[1].hasPrefix("w304"), "Second per-page call must be for page 4 (got \(perPageInputs[1]))")
    }

    // 6.8
    func testRunBatchPipelineBatchFailureFallbackPreservesRecentContext() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 20, 20, 5]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        service.failBatchForPageIds = ["3", "4"]

        await vm.loadFolder(root)

        // After batch 1 (pages 0..2) succeeds, the rolling window contains 3 summaries.
        // Page 3's fallback per-page call sees those 3 summaries; page 4's call sees the
        // window updated with page 3's translation (sliding to keep the most recent 3).
        XCTAssertEqual(service.perPageCalls.count, 2)
        let page3Summaries = service.perPageCalls[0].summaries
        XCTAssertEqual(page3Summaries.count, 3, "Page 3 must see 3 prior page summaries — got \(page3Summaries)")
        let page4Summaries = service.perPageCalls[1].summaries
        XCTAssertEqual(page4Summaries.count, 3, "Page 4 must see 3 prior page summaries — got \(page4Summaries)")
        // Page 4's window includes page 3's translation; page 0's summary is dropped.
        XCTAssertNotEqual(page3Summaries, page4Summaries, "Window must shift after page 3 succeeds")
    }

    // 6.9
    func testRunBatchPipelineCancelDuringBatchReturnsBatchPagesToPending() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        service.suspendBatchUntilCancel = true

        let task = Task { await vm.loadFolder(root) }
        // Wait for the batch to enter the suspended state. Poll perPageCalls/batchCalls.
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if service.batchCalls.count >= 1 { break }
        }
        task.cancel()
        await task.value

        for i in vm.pages.indices {
            if case .pending = vm.pages[i].state { continue }
            XCTFail("Page \(i) must return to .pending after cancel, got \(vm.pages[i].state)")
        }
        XCTAssertEqual(service.batchCalls.count, 1, "No later batch must be invoked after cancel")
    }

    // Cancellation that arrives between translateBatch returning successfully and the
    // view-model persisting outputs must still revert pages to .pending and skip persist.
    func testRunBatchPipelineCancelAfterBatchSucceedsBeforePersistRevertsPages() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let taskBox = TaskHandleBox()
        service.onBatchSuccessBeforeReturn = { @Sendable in
            taskBox.cancel()
        }

        let task = Task { await vm.loadFolder(root) }
        taskBox.set(task)
        await task.value

        for i in vm.pages.indices {
            if case .pending = vm.pages[i].state { continue }
            XCTFail("Page \(i) must return to .pending after late-cancel, got \(vm.pages[i].state)")
        }
    }

    // 6.10
    func testRunBatchPipelineCancelDuringBatchDoesNotFallbackToPerPage() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        service.suspendBatchUntilCancel = true

        let task = Task { await vm.loadFolder(root) }
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if service.batchCalls.count >= 1 { break }
        }
        task.cancel()
        await task.value

        XCTAssertEqual(service.perPageCalls.count, 0, "Cancellation must not trigger per-page fallback")
    }

    // 6.11
    func testRunBatchPipelineDeepLEngineSkipsBatchPath() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4],
            engine: .deepL
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 0, "DeepL must never call translateBatch")
        XCTAssertEqual(service.perPageCalls.count, 3, "DeepL must use per-page parallel path")
    }

    // 6.12
    func testTranslatePageSinglePageEntrySkipsBatchPath() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Manually wire one page without going through loadFolder, then call translatePage.
        let url = root.appendingPathComponent("page_1.png")
        var page = MangaPage(imageURL: url)
        page.image = NSImage(contentsOf: url)
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)

        XCTAssertEqual(service.batchCalls.count, 0, "Single-page entry must not call translateBatch")
        XCTAssertEqual(service.perPageCalls.count, 1, "Single-page entry must call translate exactly once")
    }
}
