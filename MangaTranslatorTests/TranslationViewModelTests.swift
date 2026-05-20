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
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: TrackingTranslationService())
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/same-lang-log.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)
        await DebugLogger.shared.flush()

        var filter = DebugLogFilter()
        filter.category = .pipeline
        filter.sessionIDFilter = .session(DebugLogger.shared.sessionID)
        let entries = await DebugLogStore.shared.queryAll(filter: filter)
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
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: TrackingTranslationService())
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/punct-log.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, bypassCache: true)
        await DebugLogger.shared.flush()

        var filter = DebugLogFilter()
        filter.category = .pipeline
        filter.sessionIDFilter = .session(DebugLogger.shared.sessionID)
        let entries = await DebugLogStore.shared.queryAll(filter: filter)
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

    // MARK: - Re-translate

    func testRetranslateFailurePreservesPreviousTranslations() async {
        let router = await makeRouter(recognizerText: "こんにちは")
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let translationService = QueueingTranslationService(results: [
            .success("你好"),
            .failure(TranslationError.apiError("forced retranslate failure"))
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
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
        let glossary = vm.glossaryServiceForView.createGlossary(name: "Names")
        XCTAssertNotNil(glossary)
        _ = vm.glossaryServiceForView.insertTerm(
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
