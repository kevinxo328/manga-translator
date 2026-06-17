import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

@MainActor
final class TranslationViewModelTests: XCTestCase {

    // MARK: - Engine-switch layout match (engine-switch-cache-reuse)

    private func makeTranslated(
        index: Int,
        box: CGRect,
        text: String,
        translated: String = "t",
        isManual: Bool = false
    ) -> TranslatedBubble {
        TranslatedBubble(
            bubble: BubbleCluster(boundingBox: box, text: text, observations: [], index: index, isManual: isManual),
            translatedText: translated,
            index: index
        )
    }

    func testLayoutMatchesAcceptsIdenticalLayoutWithDifferentTranslations() {
        let committed = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", translated: "engine A"),
            makeTranslated(index: 1, box: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b", translated: "engine A")
        ]
        let cached = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", translated: "engine B"),
            makeTranslated(index: 1, box: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b", translated: "engine B")
        ]
        XCTAssertTrue(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "Same layout with different translated text must match — differing translations are the point of the lookup"
        )
    }

    func testLayoutMatchesIsArrayOrderInsensitive() {
        let committed = [
            makeTranslated(index: 1, box: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b"),
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a")
        ]
        let cached = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a"),
            makeTranslated(index: 1, box: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b")
        ]
        XCTAssertTrue(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "Comparison must sort by index, not rely on array order"
        )
    }

    func testLayoutMatchesRejectsAddedBubble() {
        let committed = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a"),
            makeTranslated(index: 1, box: CGRect(x: 20, y: 0, width: 10, height: 10), text: "drawn", isManual: true)
        ]
        let cached = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a")
        ]
        XCTAssertFalse(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "A bubble drawn after the cache entry was written must invalidate the match"
        )
    }

    func testLayoutMatchesRejectsDeletedBubble() {
        let committed = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a")
        ]
        let cached = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a"),
            makeTranslated(index: 1, box: CGRect(x: 20, y: 0, width: 10, height: 10), text: "deleted")
        ]
        XCTAssertFalse(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "A stale cache entry containing a deleted bubble must not be used — it would resurrect the bubble"
        )
    }

    func testLayoutMatchesRejectsMovedBoundingBox() {
        let committed = [
            makeTranslated(index: 0, box: CGRect(x: 5, y: 5, width: 10, height: 10), text: "a", isManual: true)
        ]
        let cached = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a")
        ]
        XCTAssertFalse(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "A moved bubble must invalidate the match (exact CGRect equality, no tolerance)"
        )
    }

    func testLayoutMatchesRejectsReorderedIndices() {
        // Reorder-only edits flip no isManual flag; the index assignment is the
        // only difference. This is the case the isManual-based predicate misses.
        let boxA = CGRect(x: 0, y: 0, width: 10, height: 10)
        let boxB = CGRect(x: 20, y: 0, width: 10, height: 10)
        let committed = [
            makeTranslated(index: 0, box: boxB, text: "b"),
            makeTranslated(index: 1, box: boxA, text: "a")
        ]
        let cached = [
            makeTranslated(index: 0, box: boxA, text: "a"),
            makeTranslated(index: 1, box: boxB, text: "b")
        ]
        XCTAssertFalse(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "A reading-order change must invalidate the match even though geometry and text are unchanged"
        )
    }

    func testLayoutMatchesRejectsDifferentSourceText() {
        let committed = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "fresh OCR")
        ]
        let cached = [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "old OCR")
        ]
        XCTAssertFalse(
            TranslationViewModel.layoutMatches(committed: committed, cached: cached),
            "Differing source text means the cached translations describe different content"
        )
    }

    // MARK: - Engine-switch preparation path (engine-switch-cache-reuse)

    private final class StubCacheService: CacheServiceProtocol, @unchecked Sendable {
        var isAvailable: Bool = true
        let glossaryService = GlossaryService(db: nil, isAvailable: false)
        var lookupResult: CacheService.CachedTranslationResult?
        private(set) var lookupCount = 0
        private(set) var storedBubbleSets: [[TranslatedBubble]] = []

        func lookup(
            imageHash: String, source: Language, target: Language, engine: TranslationEngine
        ) -> CacheService.CachedTranslationResult? {
            lookupCount += 1
            return lookupResult
        }
        func translationCacheSize() -> Int64 { 0 }
        func store(
            imageHash: String, source: Language, target: Language,
            engine: TranslationEngine, bubbles: [TranslatedBubble]
        ) throws {
            storedBubbleSets.append(bubbles)
        }
        func clearAll() throws {}
    }

    // Router whose recognizer throws: any test reaching OCR errors the page,
    // so a final `.translated` state proves OCR never ran.
    private func makeThrowingOCRRouter() async -> OCRRouter {
        let service = MangaOCRService(detector: MockComicTextDetectorSingle())
        await service.setRecognizer(ThrowingOCRRecognizer())
        return OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
        )
    }

    private func makeCommittedPage(_ bubbles: [TranslatedBubble], hash: String = "hash-1") -> MangaPage {
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/engine-switch-test.png"))
        page.image = makeTestImage()
        page.imageHash = hash
        page.state = .translated(bubbles)
        return page
    }

    func testEngineSwitchUsesMatchingCacheWithoutOCROrAPI() async {
        let box0 = CGRect(x: 0, y: 0, width: 10, height: 10)
        let box1 = CGRect(x: 20, y: 0, width: 10, height: 10)
        let committed = [
            makeTranslated(index: 0, box: box0, text: "a", translated: "old A"),
            makeTranslated(index: 1, box: box1, text: "b", translated: "old A")
        ]
        let cache = StubCacheService()
        cache.lookupResult = CacheService.CachedTranslationResult(bubbles: [
            makeTranslated(index: 0, box: box0, text: "a", translated: "cached B"),
            makeTranslated(index: 1, box: box1, text: "b", translated: "cached B")
        ])
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated from cache hit, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.translatedText), ["cached B", "cached B"], "Cached translations must be displayed")
        XCTAssertFalse(translationCalled, "Matching cache hit must not call the translation service")
        XCTAssertTrue(cache.storedBubbleSets.isEmpty, "Cache hit must not write back to the cache")
        XCTAssertEqual(cache.lookupCount, 1, "Engine switch must consult the new engine's cache")
    }

    func testEngineSwitchCacheMissPreservesBubblesAndTranslatesOnly() async {
        let box0 = CGRect(x: 0, y: 0, width: 10, height: 10)
        let box1 = CGRect(x: 20, y: 0, width: 10, height: 10)
        let committed = [
            makeTranslated(index: 0, box: box0, text: "a", translated: "old"),
            makeTranslated(index: 1, box: box1, text: "b", translated: "old")
        ]
        let cache = StubCacheService() // lookupResult = nil → miss
        var translateCallCount = 0
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translateCallCount += 1 }),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated after re-translate on miss, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(translateCallCount, 1, "Cache miss must re-run translation exactly once")
        XCTAssertEqual(result.map(\.bubble.boundingBox), [box0, box1], "Committed geometry must be preserved verbatim")
        XCTAssertEqual(result.map(\.bubble.text), ["a", "b"], "Committed OCR text must be preserved verbatim")
        XCTAssertEqual(result.map(\.index), [0, 1], "Committed reading order must be preserved verbatim")
        XCTAssertEqual(cache.storedBubbleSets.count, 1, "Result must be written to the new engine's cache")
    }

    // MARK: - Translation-in-flight lock (lock-controls-during-batch)

    func testIsTranslationInFlightFalseWhenIdle() {
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: StubCacheService()
        )
        vm.pages = [makeCommittedPage([makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a")])]
        XCTAssertFalse(
            vm.isTranslationInFlight,
            "No batch and no .processing page — settings controls must stay unlocked"
        )
    }

    func testIsTranslationInFlightTrueWhileBatchFlagSet() {
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: StubCacheService()
        )
        vm.isProcessing = true
        XCTAssertTrue(
            vm.isTranslationInFlight,
            "Batch pipeline running must lock settings controls even with no page yet in .processing"
        )
    }

    func testIsTranslationInFlightTrueWhileAnyPageProcessing() {
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService(),
            cacheService: StubCacheService()
        )
        var processingPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/in-flight-test.png"))
        processingPage.state = .processing
        vm.pages = [
            makeCommittedPage([makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a")]),
            processingPage
        ]
        XCTAssertFalse(vm.isProcessing, "Precondition: single-page flows never set the batch flag")
        XCTAssertTrue(
            vm.isTranslationInFlight,
            "A single-page flow (.processing page) must lock settings controls — it reads live preferences mid-flight"
        )
    }

    func testEngineSwitchIgnoredWhileBatchRunning() async {
        let committed = [makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", translated: "old A")]
        let cache = StubCacheService()
        cache.lookupResult = CacheService.CachedTranslationResult(bubbles: [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", translated: "cached B")
        ])
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]
        vm.isProcessing = true

        await vm.switchEngineForCurrentPage()

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Engine switch during batch must not touch page state, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.translatedText), ["old A"], "Page must keep its pre-switch translations")
        XCTAssertEqual(cache.lookupCount, 0, "Suppressed switch must not consult the cache")
        XCTAssertFalse(translationCalled, "Suppressed switch must not call the translation service")
        XCTAssertTrue(cache.storedBubbleSets.isEmpty, "Suppressed switch must not write to the cache")
    }

    func testEngineSwitchIgnoredWhileAnotherPageProcessing() async {
        let committed = [makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", translated: "old A")]
        let cache = StubCacheService()
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        var processingPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/in-flight-test.png"))
        processingPage.state = .processing
        vm.pages = [makeCommittedPage(committed), processingPage]

        await vm.switchEngineForCurrentPage()

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Engine switch during a single-page flow must not touch page state, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.translatedText), ["old A"], "Page must keep its pre-switch translations")
        XCTAssertEqual(cache.lookupCount, 0, "Suppressed switch must not consult the cache")
        XCTAssertFalse(translationCalled, "Suppressed switch must not call the translation service")
    }

    func testEngineSwitchProceedsWhenNoTranslationInFlight() async {
        let box0 = CGRect(x: 0, y: 0, width: 10, height: 10)
        let committed = [makeTranslated(index: 0, box: box0, text: "a", translated: "old A")]
        let cache = StubCacheService()
        cache.lookupResult = CacheService.CachedTranslationResult(bubbles: [
            makeTranslated(index: 0, box: box0, text: "a", translated: "cached B")
        ])
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]

        await vm.switchEngineForCurrentPage()

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated from cache hit, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.translatedText), ["cached B"], "Idle engine switch must behave exactly as before the guard")
        XCTAssertEqual(cache.lookupCount, 1, "Idle engine switch must consult the new engine's cache")
    }

    func testToolbarEngineSwitchCanBeCancelled() async throws {
        let box0 = CGRect(x: 0, y: 0, width: 10, height: 10)
        let committed = [makeTranslated(index: 0, box: box0, text: "a", translated: "old A")]
        let service = SuspendingTranslationService()
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: service,
            cacheService: StubCacheService()
        )
        vm.pages = [makeCommittedPage(committed)]

        let task = try XCTUnwrap(vm.startSwitchEngineForCurrentPage())
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if service.translateCallCount > 0 { break }
        }

        XCTAssertTrue(vm.canCancelTranslation, "Engine switch launched from the toolbar must expose the same cancel action")
        vm.cancelTranslation()
        await task.value

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Cancelled engine switch must restore the previous translation, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.translatedText), ["old A"])
        XCTAssertFalse(vm.canCancelTranslation, "Cancel action must clear when the engine-switch task exits")
    }

    func testEngineSwitchStaleCacheLackingManualBubbleIsIgnored() async {
        let box0 = CGRect(x: 0, y: 0, width: 10, height: 10)
        let box1 = CGRect(x: 20, y: 0, width: 10, height: 10)
        let drawnBox = CGRect(x: 40, y: 0, width: 10, height: 10)
        let committed = [
            makeTranslated(index: 0, box: box0, text: "a"),
            makeTranslated(index: 1, box: box1, text: "b"),
            makeTranslated(index: 2, box: drawnBox, text: "drawn", isManual: true)
        ]
        let cache = StubCacheService()
        // Stale entry written before the user drew the third bubble.
        cache.lookupResult = CacheService.CachedTranslationResult(bubbles: [
            makeTranslated(index: 0, box: box0, text: "a", translated: "stale"),
            makeTranslated(index: 1, box: box1, text: "b", translated: "stale")
        ])
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated, got \(vm.pages[0].state)")
        }
        XCTAssertTrue(translationCalled, "Stale cache layout must fall back to re-translation")
        XCTAssertEqual(result.count, 3, "The drawn manual bubble must survive the engine switch")
        XCTAssertEqual(result.map(\.bubble.isManual), [false, false, true])
        XCTAssertEqual(cache.storedBubbleSets.count, 1, "Edited layout must overwrite the stale cache entry")
    }

    func testEngineSwitchReorderOnlyStaleCacheIsIgnored() async {
        // Reorder-only edits flip no isManual flag — the stale entry differs
        // only in index assignment. See design.md D2.
        let boxA = CGRect(x: 0, y: 0, width: 10, height: 10)
        let boxB = CGRect(x: 20, y: 0, width: 10, height: 10)
        let committed = [
            makeTranslated(index: 0, box: boxB, text: "b"),
            makeTranslated(index: 1, box: boxA, text: "a")
        ]
        let cache = StubCacheService()
        cache.lookupResult = CacheService.CachedTranslationResult(bubbles: [
            makeTranslated(index: 0, box: boxA, text: "a", translated: "stale"),
            makeTranslated(index: 1, box: boxB, text: "b", translated: "stale")
        ])
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated, got \(vm.pages[0].state)")
        }
        XCTAssertTrue(translationCalled, "Reordered layout must fall back to re-translation")
        XCTAssertEqual(
            result.sorted { $0.index < $1.index }.map(\.bubble.text), ["b", "a"],
            "The user's reading order must be preserved, not the stale cached order"
        )
    }

    func testEngineSwitchOnPendingPageUsesCacheHit() async {
        let cache = StubCacheService()
        cache.lookupResult = CacheService.CachedTranslationResult(bubbles: [
            makeTranslated(index: 0, box: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", translated: "cached")
        ])
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/engine-switch-pending.png"))
        page.image = makeTestImage()
        page.imageHash = "hash-pending"
        vm.pages = [page] // state stays .pending

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated from cache hit on pending page, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.translatedText), ["cached"])
        XCTAssertFalse(translationCalled, "Pending-page cache hit must not call the translation service")
    }

    func testEngineSwitchOnPendingPageMissRunsFullOCR() async {
        let cache = StubCacheService() // miss
        var translationCalled = false
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeRouter(recognizerText: "detected"),
            translationService: TrackingTranslationService(onTranslate: { translationCalled = true }),
            cacheService: cache
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/engine-switch-pending-miss.png"))
        page.image = makeTestImage()
        page.imageHash = "hash-pending-miss"
        vm.pages = [page]

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Expected .translated after full OCR fallback, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(result.map(\.bubble.text), ["detected"], "Pending page with cache miss must run the full OCR pipeline")
        XCTAssertTrue(translationCalled)
    }

    func testEngineSwitchTranslationFailureRestoresPreviousState() async {
        let box0 = CGRect(x: 0, y: 0, width: 10, height: 10)
        let committed = [makeTranslated(index: 0, box: box0, text: "a", translated: "old", isManual: true)]
        let cache = StubCacheService() // miss → must re-translate
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: await makeThrowingOCRRouter(),
            translationService: QueueingTranslationService(results: [.failure(URLError(.notConnectedToInternet))]),
            cacheService: cache
        )
        vm.pages = [makeCommittedPage(committed)]

        await vm.translatePage(at: 0, mode: .engineSwitch)

        guard case .translated(let restored) = vm.pages[0].state else {
            return XCTFail("Failed engine switch must restore previous .translated state, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(restored.map(\.translatedText), ["old"], "Previous translations must be restored on failure")
        XCTAssertEqual(restored.map(\.bubble.isManual), [true], "isManual flags must survive the failed engine switch")
        XCTAssertTrue(cache.storedBubbleSets.isEmpty, "Failed translation must not write to the cache")
    }

    // MARK: - Glossary selection

    func testCreateGlossarySelectsNewGlossary() throws {
        let cache = makeTempCache()
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            cacheService: cache
        )

        let glossary = try vm.createAndSelectGlossary(named: "  Navbar  ")

        XCTAssertEqual(vm.activeGlossaryID, glossary.id, "New glossary must become the active glossary immediately")
        XCTAssertEqual(vm.activeGlossary?.name, "Navbar")
        XCTAssertTrue(vm.glossaries.contains { $0.id == glossary.id }, "Glossary list must refresh after creation")
    }

    func testCreateGlossaryValidationFailureDoesNotMutateSelectionOrList() throws {
        let cache = makeTempCache()
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            cacheService: cache
        )
        let existing = try vm.createAndSelectGlossary(named: "Characters")
        let initialGlossaries = vm.glossaries.map { "\($0.id):\($0.name)" }
        let initialActiveID = vm.activeGlossaryID

        for invalidName in ["   ", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "  Characters  "] {
            XCTAssertThrowsError(try vm.createAndSelectGlossary(named: invalidName))
            XCTAssertEqual(
                vm.glossaries.map { "\($0.id):\($0.name)" },
                initialGlossaries,
                "Failed create must not append a glossary for \(invalidName)"
            )
            XCTAssertEqual(vm.activeGlossaryID, initialActiveID, "Failed create must not change selection for \(invalidName)")
            XCTAssertEqual(vm.activeGlossary?.id, existing.id)
        }
    }

    func testRenameGlossaryValidationFailureDoesNotMutateCachedNameOrSelection() throws {
        let cache = makeTempCache()
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            cacheService: cache
        )
        let characters = try vm.createAndSelectGlossary(named: "Characters")
        let places = try vm.createAndSelectGlossary(named: "Places")
        vm.activeGlossaryID = places.id

        for invalidName in ["   ", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "  Characters  "] {
            XCTAssertThrowsError(try vm.renameGlossary(id: places.id, to: invalidName))
            XCTAssertEqual(vm.glossaries.first { $0.id == characters.id }?.name, "Characters")
            XCTAssertEqual(vm.glossaries.first { $0.id == places.id }?.name, "Places")
            XCTAssertEqual(vm.activeGlossaryID, places.id, "Failed rename must not change active selection for \(invalidName)")
        }
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

        await vm.translatePage(at: 0, mode: .retranslate)

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

        await vm.translatePage(at: 0, mode: .retranslate)
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

        await vm.translatePage(at: 0, mode: .retranslate)
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
        await vm.translatePage(at: 0, mode: .retranslate)
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
        await vm.translatePage(at: 0, mode: .retranslate)
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
        await vm.translatePage(at: 0, mode: .retranslate)
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
        await vm.translatePage(at: 0, mode: .retranslate)
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

        await vm.translatePage(at: 0, mode: .retranslate)

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

        await vm.translatePage(at: 0, mode: .retranslate)
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

    // 3.1 clearAll failure → no page state changes.
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
        var errorPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/preserve-2.jpg"))
        errorPage.state = .error("frozen error")
        vm.pages = [translatedPage, errorPage]

        vm.clearCacheAndResetPages()

        guard case .translated(let preservedBubbles) = vm.pages[0].state else {
            return XCTFail("Expected page 0 state preserved as .translated, got \(vm.pages[0].state)")
        }
        XCTAssertEqual(preservedBubbles.first?.translatedText, "舊")
        guard case .error(let preservedMessage) = vm.pages[1].state else {
            return XCTFail("Expected page 1 state preserved as .error, got \(vm.pages[1].state)")
        }
        XCTAssertEqual(preservedMessage, "frozen error")
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
        var errorPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/reset-2.jpg"))
        errorPage.state = .error("old error")
        vm.pages = [translatedPage, errorPage]

        vm.clearCacheAndResetPages()

        for page in vm.pages {
            guard case .pending = page.state else {
                return XCTFail("Expected every page reset to .pending, got \(page.state)")
            }
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

        await vm.translatePage(at: 0, mode: .retranslate)
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
        var errorPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/page-2.jpg"))
        errorPage.state = .error("old error")
        vm.pages = [translatedPage, errorPage]

        vm.clearCacheAndResetPages()

        for page in vm.pages {
            guard case .pending = page.state else {
                return XCTFail("Expected every loaded page to reset to pending, got \(page.state)")
            }
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

        await vm.translatePage(at: 0, mode: .retranslate)

        XCTAssertEqual(translationService.contexts.last?.glossaryTerms.first?.sourceTerm, "太郎")
        XCTAssertEqual(translationService.contexts.last?.glossaryTerms.first?.targetTerm, "太郎")
    }

    // The glossary accumulates auto-detected terms over a whole series; sending
    // all of them with every page makes prompt token cost grow linearly. Only
    // terms whose source occurs in the page's OCR text may reach the context.
    func testTranslationContextOmitsGlossaryTermsAbsentFromPage() async {
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
            targetTerm: "Taro",
            autoDetected: false
        )
        _ = try? vm.glossaryServiceForView.addTerm(
            glossaryID: glossary!.id,
            sourceTerm: "花子",
            targetTerm: "Hanako",
            autoDetected: true
        )
        vm.loadGlossaries()
        vm.activeGlossaryID = glossary?.id
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/glossary-filter.jpg"))
        page.image = makeTestImage()
        vm.pages = [page]

        await vm.translatePage(at: 0, mode: .retranslate)

        XCTAssertEqual(
            translationService.contexts.last?.glossaryTerms.map(\.sourceTerm),
            ["太郎"],
            "Terms absent from the page's source text must not be sent to the service"
        )
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
            await vm.translatePage(at: index, mode: .retranslate)
        }

        XCTAssertEqual(translationService.contexts.count, 4)
        XCTAssertEqual(translationService.contexts[0].recentPageSummaries, [])
        XCTAssertEqual(translationService.contexts[3].recentPageSummaries, ["T:p1", "T:p2", "T:p3"])
    }

    // A page with no meaningful bubbles (title page, pure artwork) must not
    // push an empty summary into the rolling 3-page context window — empty
    // entries evict real summaries and degrade translation consistency on
    // later pages.
    func testPageWithNoMeaningfulBubblesDoesNotConsumeRecentContextWindow() async {
        let router = await makeSingleRegionRouterSequential(texts: ["p1", "", "p3", "p4"])
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let translationService = CapturingTranslationService()
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: translationService)
        vm.pages = (0..<4).map { index in
            var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/empty-context-\(index).jpg"))
            page.image = makeTestImage()
            return page
        }

        for index in 0..<4 {
            await vm.translatePage(at: index, mode: .retranslate)
        }

        // Page 2 OCRs to empty text and is skipped, so only 3 pages reach
        // the translation service. Page 4's context must contain both real
        // summaries with no empty placeholder between them.
        XCTAssertEqual(translationService.contexts.count, 3)
        XCTAssertEqual(translationService.contexts.last?.recentPageSummaries, ["T:p1", "T:p3"])
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

    // Multi-volume folders (vol1/, vol2/, …) must keep each volume's pages
    // together in reading order. Sorting by filename alone interleaves pages
    // from different volumes that share the same numbering.
    func testScanFolderKeepsVolumesTogetherInsteadOfInterleavingByFilename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vol1 = root.appendingPathComponent("vol1")
        let vol2 = root.appendingPathComponent("vol2")
        try FileManager.default.createDirectory(at: vol1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vol2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            vol1.appendingPathComponent("page_1.jpg"),
            vol1.appendingPathComponent("page_3.jpg"),
            vol2.appendingPathComponent("page_2.jpg")
        ]
        for url in files {
            try Data("x".utf8).write(to: url)
        }

        let scanned = FileInputService.scanFolder(root).map {
            $0.pathComponents.suffix(2).joined(separator: "/")
        }

        XCTAssertEqual(scanned, ["vol1/page_1.jpg", "vol1/page_3.jpg", "vol2/page_2.jpg"])
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

    // Decoded bitmaps are the dominant per-page memory cost (a 1MB JPEG can
    // decode to tens of MB). The viewer only ever shows the current page, so
    // after a batch run only the sliding window (current ± 1) may stay
    // resident; every other page must hold just its URL and reload lazily.
    func testLoadFolderKeepsOnlyImageWindowResidentAfterBatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 1...6 {
            try writeTestPNG(at: root.appendingPathComponent("page_\(index).png"))
        }

        let router = await makeSingleRegionRouterSequential(texts: ["page"])
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: TrackingTranslationService()
        )

        await vm.loadFolder(root)

        XCTAssertEqual(vm.currentPageIndex, 0)
        XCTAssertNotNil(vm.pages[0].image, "current page must stay resident for the viewer")
        XCTAssertNotNil(vm.pages[1].image, "next page is preloaded so page-flip is instant")
        for index in 2...5 {
            XCTAssertNil(vm.pages[index].image, "page \(index) is outside the window and must be evicted after OCR")
        }
        // Eviction must drop only the decoded bitmap — translation results and
        // the cache key survive so no work is redone when the page is revisited.
        for index in 2...5 {
            XCTAssertNotNil(vm.pages[index].imageHash)
            guard case .translated = vm.pages[index].state else {
                XCTFail("page \(index) should remain translated after eviction")
                continue
            }
        }
    }

    func testNavigationSlidesImageWindowAndReloadsLazily() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 1...6 {
            try writeTestPNG(at: root.appendingPathComponent("page_\(index).png"))
        }

        let router = await makeSingleRegionRouterSequential(texts: ["page"])
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: TrackingTranslationService()
        )
        await vm.loadFolder(root)

        vm.nextPage()
        vm.nextPage()

        XCTAssertEqual(vm.currentPageIndex, 2)
        XCTAssertNil(vm.pages[0].image, "page left behind the window must be released")
        XCTAssertNotNil(vm.pages[1].image)
        XCTAssertNotNil(vm.pages[2].image)
        XCTAssertNotNil(vm.pages[3].image, "evicted page ahead must reload when the window reaches it")
        XCTAssertNil(vm.pages[4].image)
        XCTAssertNil(vm.pages[5].image)
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
        // Six pages span three LLM batches under the ramp caps (1, 3, 5):
        // [p1], [p2, p3, p4], [p5, p6]. The within-batch priorContext is
        // sampled once at the batch boundary; pages internal to a batch share
        // that context.
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
        // Batch 1 (page 1): priorContext is empty (no successful page with index < 1).
        // The default TranslationService.translateBatch extension delegates to per-page
        // translate(...) so each recorded call observes the same batch-level priorContext.
        XCTAssertEqual(translationService.context(forInput: "p1")?.recentPageSummaries, [])
        // Batch 2 (pages 2..4): window observed at the boundary contains page 1 only.
        for text in ["p2", "p3", "p4"] {
            XCTAssertEqual(
                translationService.context(forInput: text)?.recentPageSummaries,
                ["T:p1"],
                "Within-batch pages share the batch-level priorContext (\(text))"
            )
        }
        // Batch 3 (pages 5, 6): rolling window after batch 2 is trimmed to last 3.
        for text in ["p5", "p6"] {
            XCTAssertEqual(
                translationService.context(forInput: text)?.recentPageSummaries,
                ["T:p2", "T:p3", "T:p4"],
                "Within-batch pages share the batch-level priorContext (\(text))"
            )
        }
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
        }
        // Glossary still flows to non-LLM engines, filtered per page: only the
        // page whose source text contains "q1" carries the term.
        XCTAssertEqual(translationService.context(forInput: "q1")?.glossaryTerms.map(\.sourceTerm), ["q1"])
        XCTAssertEqual(translationService.context(forInput: "q1")?.glossaryTerms.map(\.targetTerm), ["Q1"])
        for input in ["q2", "q3", "q4"] {
            XCTAssertEqual(
                translationService.context(forInput: input)?.glossaryTerms.isEmpty,
                true,
                "Pages without the term must not carry it (\(input))"
            )
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
        // Relaxed for the producer/consumer pipeline (see
        // producer-consumer-llm-pipeline design D5, pre-announced by the
        // fix-batch-recent-context-order design note): page 1's own OCR must
        // precede the first LLM translation; later pages' OCR may interleave.
        XCTAssertGreaterThanOrEqual(
            translationService.ocrCountAtFirstTranslate ?? 0,
            1,
            "OCR for page 1 must complete before the first LLM translation starts"
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
        // Ramp groups for the retranslate pass: [u1], [u2, u3, u4], [u5, u6].
        XCTAssertEqual(retranslate["u1"], [], "First batch has no prior context")
        for text in ["u2", "u3", "u4"] {
            XCTAssertEqual(retranslate[text], ["T:u1"], "Within-batch \(text)")
        }
        // Batch 3 (u5, u6): rolling window after batch 2 trimmed to last 3.
        for text in ["u5", "u6"] {
            XCTAssertEqual(retranslate[text], ["T:u2", "T:u3", "T:u4"], "Within-batch \(text)")
        }
    }

    // producer-consumer-llm-pipeline: the first LLM batch must dispatch after
    // page 1's own preparation, not after all pages prepare. Each page's OCR
    // takes ~120ms on the serial OCR actor, so if the first translation only
    // starts once every page is prepared (two-phase pipeline), the OCR observer
    // count at that moment equals the page count; pipelined dispatch sees far
    // fewer. This is the time-to-first-readable-page property.
    func testFirstLLMBatchDispatchesBeforeLaterPreparationsComplete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let widths = [171, 172, 173, 174]
        let texts = ["v1", "v2", "v3", "v4"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        for (i, width) in widths.enumerated() {
            try writeUniqueColoredPNG(at: root.appendingPathComponent("page_\(i + 1).png"), width: width)
        }

        let recognizer = DelayingSizeMappedOCRRecognizer(textByWidth: textByWidth, delay: 0.12)
        let translationService = OrderedContextRecorder(engine: .githubCopilot, ocrObserver: recognizer.inner)
        let service = MangaOCRService(detector: MockComicTextDetectorSingle())
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
        )
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: router,
            translationService: translationService,
            cacheService: makeTempCache()
        )
        vm.clearCacheAndResetPages()

        await vm.loadFolder(root)

        XCTAssertEqual(translationService.callCount, 4)
        let observed = try XCTUnwrap(translationService.ocrCountAtFirstTranslate)
        XCTAssertLessThanOrEqual(
            observed, 2,
            "First LLM batch must not wait for all pages' OCR (observed \(observed)/\(widths.count) at first translate)"
        )
    }

    // producer-consumer-llm-pipeline: a preparation that completes early (cache
    // hit while earlier pages are still in OCR) must not be consumed out of
    // order. Page 3 is cached and ready instantly; pages 1 and 2 are slowed by
    // OCR. Page 4's batch context must still list pages 1, 2, 3 ascending.
    // Pinning test: also holds on the two-phase pipeline.
    func testCacheHitPreparedEarlyIsConsumedInPageOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let widths = [181, 182, 183, 184]
        let texts = ["x1", "x2", "x3", "x4"]
        let textByWidth = Dictionary(uniqueKeysWithValues: zip(widths, texts))
        for (i, width) in widths.enumerated() {
            try writeUniqueColoredPNG(at: root.appendingPathComponent("page_\(i + 1).png"), width: width)
        }

        let recognizer = DelayingSizeMappedOCRRecognizer(textByWidth: textByWidth, delay: 0.08)
        let translationService = OrderedContextRecorder(engine: .githubCopilot, ocrObserver: recognizer.inner)
        let service = MangaOCRService(detector: MockComicTextDetectorSingle())
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
        )
        let cache = makeTempCache()
        let prefs = makePrefs(source: .ja, target: .zhHant)
        prefs.translationEngine = .githubCopilot
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: translationService,
            cacheService: cache
        )
        vm.clearCacheAndResetPages()

        // Pre-populate the cache for page 3 so its preparation completes
        // without touching the (slow) OCR actor.
        let page3Data = try Data(contentsOf: root.appendingPathComponent("page_3.png"))
        try cache.store(
            imageHash: CacheService.imageHash(data: page3Data),
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [TranslatedBubble(
                bubble: BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "x3", observations: []),
                translatedText: "T:x3-cached",
                index: 0
            )]
        )

        await vm.loadFolder(root)

        XCTAssertEqual(translationService.callOrderInputs, ["x1", "x2", "x4"],
                       "Cached page 3 must not be translated; misses stay in page order")
        XCTAssertEqual(
            translationService.context(forInput: "x4")?.recentPageSummaries,
            ["T:x1", "T:x2", "T:x3-cached"],
            "Page 4 must see pages 1, 2, 3 ascending — cached page 3 consumed in order despite preparing first"
        )
        guard case .translated = vm.pages[2].state else {
            return XCTFail("Cached page 3 must finalize as translated, got \(vm.pages[2].state)")
        }
    }

    // MARK: - summariesPreceding (manual-bubble-editing change)

    func testSummariesPrecedingReturnsUpToCountTranslatedEntriesInOrder() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: TrackingTranslationService())
        vm.pages = (0..<6).map { i in
            var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p\(i).jpg"))
            page.state = .translated([makeTranslated(text: "p\(i)", index: 0)])
            return page
        }

        let summaries = vm.summariesPreceding(pageIndex: 5, count: 3)
        // 5 preceding translated pages (0..4); keep the last 3 in ascending order.
        XCTAssertEqual(summaries, ["p2", "p3", "p4"])
    }

    func testSummariesPrecedingSkipsNonTranslatedPages() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: TrackingTranslationService())
        vm.pages = (0..<6).map { i in
            var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p\(i).jpg"))
            switch i {
            case 0: page.state = .translated([makeTranslated(text: "p0", index: 0)])
            case 1: page.state = .error("boom")
            case 2: page.state = .translated([makeTranslated(text: "p2", index: 0)])
            case 3: page.state = .pending
            case 4: page.state = .translated([makeTranslated(text: "p4", index: 0)])
            default: page.state = .pending
            }
            return page
        }

        let summaries = vm.summariesPreceding(pageIndex: 5, count: 3)
        XCTAssertEqual(summaries, ["p0", "p2", "p4"])
    }

    func testSummariesPrecedingReturnsEmptyForFirstPage() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: TrackingTranslationService())
        vm.pages = (0..<3).map { i in
            var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p\(i).jpg"))
            page.state = .translated([makeTranslated(text: "p\(i)", index: 0)])
            return page
        }

        XCTAssertTrue(vm.summariesPreceding(pageIndex: 0).isEmpty)
    }

    func testSummariesPrecedingConcatenatesBubbleTextsInIndexOrder() {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(preferences: prefs, ocrRouter: makeEmptyRouter(), translationService: TrackingTranslationService())
        // Page 0 has three translated bubbles supplied OUT of index order.
        let unordered: [TranslatedBubble] = [
            makeTranslated(text: "third", index: 2),
            makeTranslated(text: "first", index: 0),
            makeTranslated(text: "second", index: 1)
        ]
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p0.jpg"))
        page.state = .translated(unordered)
        var nextPage = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p1.jpg"))
        nextPage.state = .pending
        vm.pages = [page, nextPage]

        let summaries = vm.summariesPreceding(pageIndex: 1)
        XCTAssertEqual(summaries, ["first second third"])
    }

    private func makeTranslated(text: String, index: Int) -> TranslatedBubble {
        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
            text: text,
            observations: [],
            index: index
        )
        return TranslatedBubble(bubble: bubble, translatedText: text, index: index)
    }

    // MARK: - Edit session lifecycle (manual-bubble-editing change)

    func testOpenEditSessionCapturesBubblesAndPageState() {
        let vm = makeEditVM()
        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "hi",
            observations: [],
            index: 0
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p0.jpg"))
        page.state = .translated([TranslatedBubble(bubble: bubble, translatedText: "嗨", index: 0)])
        vm.pages = [page]

        vm.openEditSession(pageId: vm.pages[0].id)

        XCTAssertNotNil(vm.editSession)
        XCTAssertEqual(vm.editSession?.workingBubbles.first?.id, bubble.id)
        XCTAssertEqual(vm.editSession?.originalSnapshot.count, 1)
        if case .translated(let snapshotBubbles) = vm.editSession?.originalPageState {
            XCTAssertEqual(snapshotBubbles.count, 1)
        } else {
            XCTFail("originalPageState should be .translated at open")
        }
    }

    func testOpenEditSessionRejectsNonTranslatedStates() {
        let vm = makeEditVM()
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p0.jpg"))
        page.state = .processing
        vm.pages = [page]

        vm.openEditSession(pageId: vm.pages[0].id)
        XCTAssertNil(vm.editSession)

        vm.pages[0].state = .error("boom")
        vm.openEditSession(pageId: vm.pages[0].id)
        XCTAssertNil(vm.editSession)

        vm.pages[0].state = .pending
        vm.openEditSession(pageId: vm.pages[0].id)
        XCTAssertNil(vm.editSession)
    }

    func testCancelRestoresSnapshotBubblesAndState() {
        let vm = makeEditVM()
        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "orig",
            observations: [],
            index: 0
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p0.jpg"))
        page.state = .translated([TranslatedBubble(bubble: bubble, translatedText: "原始", index: 0)])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        // Mutate the working copy via a forward action.
        let newBox = BubbleCluster(
            boundingBox: CGRect(x: 50, y: 50, width: 30, height: 30),
            text: "",
            observations: [],
            isManual: true
        )
        vm.applyEditAction(.add(newBox))
        XCTAssertEqual(vm.editSession?.workingBubbles.count, 2)

        vm.cancelEditSession()

        XCTAssertNil(vm.editSession)
        guard case .translated(let restored) = vm.pages[0].state else {
            return XCTFail("Page should be .translated after Cancel")
        }
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.bubble.id, bubble.id)
    }

    func testCancelAfterFailedCommitClearsErrorState() {
        let vm = makeEditVM()
        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
            text: "x",
            observations: [],
            index: 0
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p0.jpg"))
        let original: [TranslatedBubble] = [TranslatedBubble(bubble: bubble, translatedText: "x", index: 0)]
        page.state = .translated(original)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        // Simulate a failed commit: page sits in .error, session is still open.
        vm.pages[0].state = .error("simulated network failure")

        vm.cancelEditSession()

        XCTAssertNil(vm.editSession)
        guard case .translated(let restored) = vm.pages[0].state else {
            return XCTFail("Page should be .translated after Cancel-after-failure")
        }
        XCTAssertEqual(restored.map(\.bubble.id), original.map(\.bubble.id))
    }

    func testApplyAddPlacesBubbleAfterNearestNeighbour() {
        // Three pre-existing bubbles at known centres; the new bubble's
        // centre is closest to bubble at index 1. The new bubble SHALL
        // land at array position 2 with redensified indices `0..<4`.
        // Plain-append behaviour SHALL produce a different result and
        // is rejected.
        let vm = makeEditVM()
        let b0 = BubbleCluster(
            boundingBox: CGRect(x: 80, y: 80, width: 40, height: 40),
            text: "0", observations: [], index: 0
        )
        let b1 = BubbleCluster(
            boundingBox: CGRect(x: 480, y: 80, width: 40, height: 40),
            text: "1", observations: [], index: 1
        )
        let b2 = BubbleCluster(
            boundingBox: CGRect(x: 80, y: 480, width: 40, height: 40),
            text: "2", observations: [], index: 2
        )
        let page = makeTranslatedPage(with: [b0, b1, b2])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Nearest to b1 (centre 500, 100) is at (500, 110).
        let newBubble = BubbleCluster(
            boundingBox: CGRect(x: 480, y: 90, width: 40, height: 40),
            text: "", observations: [], isManual: true
        )
        vm.applyEditAction(.add(newBubble))

        let workingIds = vm.editSession?.workingBubbles.map(\.id) ?? []
        XCTAssertEqual(workingIds, [b0.id, b1.id, newBubble.id, b2.id])
        XCTAssertEqual(vm.editSession?.workingBubbles.map(\.index), [0, 1, 2, 3])
        // Plain-append would put the new bubble at position 3 — verify
        // that's NOT what happened.
        XCTAssertNotEqual(workingIds.last, newBubble.id)
    }

    func testMoveFirstFlipsIsManualAndSubsequentMovesDoNotResetIt() {
        let vm = makeEditVM()
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "auto", observations: [], index: 0, isManual: false
        )
        let page = makeTranslatedPage(with: [b])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // First move: isManual flips false → true.
        let r1 = CGRect(x: 10, y: 0, width: 40, height: 40)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: r1))
        XCTAssertEqual(vm.editSession?.workingBubbles[0].isManual, true)

        // Second move: isManual stays true.
        let r2 = CGRect(x: 20, y: 0, width: 40, height: 40)
        vm.applyEditAction(.move(id: b.id, from: r1, to: r2))
        XCTAssertEqual(vm.editSession?.workingBubbles[0].isManual, true)
    }

    func testUndoMoveRestoresBoundingBoxButKeepsIsManualSticky() {
        let vm = makeEditVM()
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "auto", observations: [], index: 0, isManual: false
        )
        let page = makeTranslatedPage(with: [b])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        let from = b.boundingBox
        let to = CGRect(x: 30, y: 0, width: 40, height: 40)
        vm.applyEditAction(.move(id: b.id, from: from, to: to))
        XCTAssertEqual(vm.editSession?.workingBubbles[0].boundingBox, to)
        XCTAssertEqual(vm.editSession?.workingBubbles[0].isManual, true)

        vm.undo()
        XCTAssertEqual(vm.editSession?.workingBubbles[0].boundingBox, from)
        XCTAssertEqual(vm.editSession?.workingBubbles[0].isManual, true) // sticky

        // Redo: bbox back to `to`; isManual still true.
        vm.redo()
        XCTAssertEqual(vm.editSession?.workingBubbles[0].boundingBox, to)
        XCTAssertEqual(vm.editSession?.workingBubbles[0].isManual, true)
    }

    func testNewMutationAfterUndoClearsRedoStack() {
        let vm = makeEditVM()
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "a", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        vm.applyEditAction(.move(
            id: b.id,
            from: b.boundingBox,
            to: CGRect(x: 5, y: 0, width: 40, height: 40)
        ))
        vm.undo()
        XCTAssertEqual(vm.editSession?.redoStack.count, 1)

        // New mutation clears redo.
        vm.applyEditAction(.delete(b))
        XCTAssertTrue(vm.editSession?.redoStack.isEmpty ?? false)
    }

    func testDeleteUndoOnlyRemovesIdFromDeletedSetLeavingWorkingCopyIntact() {
        let vm = makeEditVM()
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "x", observations: [], index: 0, isManual: false
        )
        let page = makeTranslatedPage(with: [b])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        vm.applyEditAction(.delete(b))
        XCTAssertEqual(vm.editSession?.deletedBubbleIds, [b.id])
        // Staging never removes from workingBubbles.
        XCTAssertEqual(vm.editSession?.workingBubbles.first?.id, b.id)

        vm.undo()
        XCTAssertTrue(vm.editSession?.deletedBubbleIds.isEmpty ?? false)
        // Bubble identity, geometry, text untouched.
        let restored = vm.editSession?.workingBubbles.first
        XCTAssertEqual(restored?.id, b.id)
        XCTAssertEqual(restored?.boundingBox, b.boundingBox)
        XCTAssertEqual(restored?.text, b.text)
    }

    func testFullUndoRedoCycleRestoresGeometryAndOrderByteForByte() {
        let vm = makeEditVM()
        let b1 = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "1", observations: [], index: 0
        )
        let b2 = BubbleCluster(
            boundingBox: CGRect(x: 100, y: 0, width: 40, height: 40),
            text: "2", observations: [], index: 1
        )
        let page = makeTranslatedPage(with: [b1, b2])
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        let r2 = CGRect(x: 20, y: 5, width: 40, height: 40)
        vm.applyEditAction(.resize(id: b1.id, from: b1.boundingBox, to: r2))
        vm.applyEditAction(.reorder(from: [b1.id, b2.id], to: [b2.id, b1.id]))
        XCTAssertEqual(vm.editSession?.workingBubbles.map(\.id), [b2.id, b1.id])
        XCTAssertEqual(vm.editSession?.workingBubbles.first(where: { $0.id == b1.id })?.boundingBox, r2)

        // Undo reorder.
        vm.undo()
        XCTAssertEqual(vm.editSession?.workingBubbles.map(\.id), [b1.id, b2.id])
        XCTAssertEqual(vm.editSession?.workingBubbles.map(\.index), [0, 1])

        // Undo resize.
        vm.undo()
        XCTAssertEqual(vm.editSession?.workingBubbles[0].boundingBox, b1.boundingBox)
        XCTAssertEqual(vm.editSession?.workingBubbles[0].text, b1.text)
    }

    private func makeEditVM() -> TranslationViewModel {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        return TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: TrackingTranslationService()
        )
    }

    private func makeTranslatedPage(with bubbles: [BubbleCluster]) -> MangaPage {
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/p-\(UUID().uuidString).jpg"))
        page.image = makeTestImage()
        page.imageHash = "edit-commit-hash-\(UUID().uuidString)"
        let translated: [TranslatedBubble] = bubbles.map {
            TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index)
        }
        page.state = .translated(translated)
        return page
    }

    // MARK: - Commit pipeline (manual-bubble-editing change)

    func testCommitWithUnchangedFinalStateSkipsOCRTranslatorCacheAndClosesSession() async {
        let existing = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "old", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [existing])
        let recordingTS = RecordingTranslationService(throwOnTranslate: SimulatedTranslateError.network)
        let recordingOCR = RecordingEditModeOCR(text: "should-not-run")
        let cache = CapturingCacheService()
        let vm = makeEditVM(translation: recordingTS, editOCR: recordingOCR, cache: cache)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        await vm.commitEditSession()

        XCTAssertTrue(recordingOCR.recognisedIDs.isEmpty)
        XCTAssertEqual(recordingTS.translateCalls.count, 0)
        XCTAssertEqual(recordingTS.batchCalls.count, 0)
        XCTAssertTrue(cache.storedBubbleSets.isEmpty)
        if case .translated(let result) = vm.pages[0].state {
            XCTAssertEqual(result.map(\.bubble.id), [existing.id])
            XCTAssertEqual(result.first?.translatedText, "old")
        } else {
            XCTFail("No-op commit should leave page .translated")
        }
        XCTAssertNil(vm.editSession)
    }

    func testCommitWithOnlyNewBoxRunsOCROnlyOnNewAndTranslatesAllNonDeleted() async {
        let existing = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "old", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [existing])
        let recordingTS = RecordingTranslationService()
        let recordingOCR = RecordingEditModeOCR(text: "freshly-ocred")
        let vm = makeEditVM(translation: recordingTS, editOCR: recordingOCR)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        let drawn = BubbleCluster(
            boundingBox: CGRect(x: 100, y: 100, width: 40, height: 40),
            text: "", observations: [], isManual: true
        )
        vm.applyEditAction(.add(drawn))

        await vm.commitEditSession()

        // OCR ran exactly on the new bubble.
        XCTAssertEqual(recordingOCR.recognisedIDs, [drawn.id])
        // Translator received both bubbles in working order.
        let lastCall = recordingTS.translateCalls.last
        XCTAssertEqual(lastCall?.bubbles.map(\.id), [existing.id, drawn.id])
        // The new bubble received the OCR-recognised text on its way into translate.
        XCTAssertEqual(lastCall?.bubbles.last?.text, "freshly-ocred")
        XCTAssertEqual(lastCall?.bubbles.first?.text, "old")
        // Translator received the per-page entry point, not the batch entry.
        XCTAssertEqual(recordingTS.batchCalls.count, 0)
        // Page state and session terminated correctly.
        if case .translated(let result) = vm.pages[0].state {
            XCTAssertEqual(result.count, 2)
        } else {
            XCTFail("Commit should leave page .translated")
        }
        XCTAssertNil(vm.editSession)
    }

    func testCommitWithOnlyDeletionsSkipsOCRAndPassesSurvivorsToTranslator() async {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "A", observations: [], index: 0
        )
        let b = BubbleCluster(
            boundingBox: CGRect(x: 30, y: 0, width: 20, height: 20),
            text: "B", observations: [], index: 1
        )
        let c = BubbleCluster(
            boundingBox: CGRect(x: 60, y: 0, width: 20, height: 20),
            text: "C", observations: [], index: 2
        )
        let page = makeTranslatedPage(with: [a, b, c])
        let recordingTS = RecordingTranslationService()
        let recordingOCR = RecordingEditModeOCR(text: "should-not-be-used")
        let vm = makeEditVM(translation: recordingTS, editOCR: recordingOCR)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Stage b for deletion; leave a and c intact.
        vm.applyEditAction(.delete(b))

        await vm.commitEditSession()

        XCTAssertTrue(recordingOCR.recognisedIDs.isEmpty,
                      "OCR must not run when no bubble's geometry changed")
        let lastCall = recordingTS.translateCalls.last
        XCTAssertEqual(lastCall?.bubbles.map(\.id), [a.id, c.id])
        XCTAssertFalse(lastCall?.bubbles.contains(where: { $0.id == b.id }) ?? true,
                       "Deleted bubble must not be in the translate input")
        XCTAssertEqual(recordingTS.batchCalls.count, 0)
    }

    func testCommitWithOnlyReorderSkipsOCRAndPassesNewOrderToTranslator() async {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "A", observations: [], index: 0
        )
        let b = BubbleCluster(
            boundingBox: CGRect(x: 30, y: 0, width: 20, height: 20),
            text: "B", observations: [], index: 1
        )
        let c = BubbleCluster(
            boundingBox: CGRect(x: 60, y: 0, width: 20, height: 20),
            text: "C", observations: [], index: 2
        )
        let page = makeTranslatedPage(with: [a, b, c])
        let recordingTS = RecordingTranslationService()
        let recordingOCR = RecordingEditModeOCR(text: "should-not-be-used")
        let vm = makeEditVM(translation: recordingTS, editOCR: recordingOCR)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        vm.applyEditAction(.reorder(
            from: [a.id, b.id, c.id],
            to:   [c.id, a.id, b.id]
        ))

        await vm.commitEditSession()

        XCTAssertTrue(recordingOCR.recognisedIDs.isEmpty)
        let lastCall = recordingTS.translateCalls.last
        XCTAssertEqual(lastCall?.bubbles.map(\.id), [c.id, a.id, b.id])
        // Indices densified `0..<3` in the new order.
        XCTAssertEqual(lastCall?.bubbles.map(\.index), [0, 1, 2])
    }

    func testMoveThenUndoToOriginalSkipsOCRTranslatorCacheAndDoesNotCommitStickyManual() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "untouched", observations: [], index: 0, isManual: false
        )
        let page = makeTranslatedPage(with: [b])
        let recordingTS = RecordingTranslationService(throwOnTranslate: SimulatedTranslateError.network)
        let recordingOCR = RecordingEditModeOCR(text: "should-not-be-used")
        let cache = CapturingCacheService()
        let vm = makeEditVM(translation: recordingTS, editOCR: recordingOCR, cache: cache)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Move then undo so the bbox returns to the snapshot value.
        let moved = CGRect(x: 30, y: 0, width: 40, height: 40)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: moved))
        vm.undo()

        await vm.commitEditSession()

        XCTAssertTrue(recordingOCR.recognisedIDs.isEmpty)
        XCTAssertEqual(recordingTS.translateCalls.count, 0)
        XCTAssertEqual(recordingTS.batchCalls.count, 0)
        XCTAssertTrue(cache.storedBubbleSets.isEmpty)
        if case .translated(let result) = vm.pages[0].state {
            XCTAssertEqual(result.first?.bubble.isManual, false)
            XCTAssertEqual(result.first?.translatedText, "untouched")
        } else {
            XCTFail("No-op commit should restore the original translated page")
        }
        XCTAssertNil(vm.editSession)
    }

    func testAddThenUndoToOriginalSkipsOCRTranslatorAndCache() async {
        let existing = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "old", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [existing])
        let recordingTS = RecordingTranslationService(throwOnTranslate: SimulatedTranslateError.network)
        let recordingOCR = RecordingEditModeOCR(text: "should-not-run")
        let cache = CapturingCacheService()
        let vm = makeEditVM(translation: recordingTS, editOCR: recordingOCR, cache: cache)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        let drawn = BubbleCluster(
            boundingBox: CGRect(x: 100, y: 100, width: 40, height: 40),
            text: "", observations: [], isManual: true
        )
        vm.applyEditAction(.add(drawn))
        vm.undo()

        await vm.commitEditSession()

        XCTAssertTrue(recordingOCR.recognisedIDs.isEmpty)
        XCTAssertEqual(recordingTS.translateCalls.count, 0)
        XCTAssertEqual(recordingTS.batchCalls.count, 0)
        XCTAssertTrue(cache.storedBubbleSets.isEmpty)
        if case .translated(let result) = vm.pages[0].state {
            XCTAssertEqual(result.map(\.bubble.id), [existing.id])
        } else {
            XCTFail("Add-then-undo commit should restore the original translated page")
        }
        XCTAssertNil(vm.editSession)
    }

    func testCommitFailureKeepsSessionAndSetsErrorState() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let throwingTS = RecordingTranslationService(throwOnTranslate: SimulatedTranslateError.network)
        let recordingOCR = RecordingEditModeOCR(text: "ok")
        let vm = makeEditVM(translation: throwingTS, editOCR: recordingOCR)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Force OCR-dirty so commit reaches the translator.
        let moved = CGRect(x: 10, y: 0, width: 20, height: 20)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: moved))

        await vm.commitEditSession()

        XCTAssertNotNil(vm.editSession, "Session stays open so the user can retry or cancel")
        if case .error(let message) = vm.pages[0].state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Page state should be .error after a translator throw")
        }
    }

    func testCommitWithEmptyFinalSetSkipsOCRTranslatorAndNeverEntersProcessing() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        // Translator rigged to throw on ANY call — short-circuit must keep us
        // from ever invoking it.
        let translator = RecordingTranslationService(throwOnTranslate: SimulatedTranslateError.network)
        let ocr = RecordingEditModeOCR(text: "should-not-run")
        let vm = makeEditVM(translation: translator, editOCR: ocr)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        vm.applyEditAction(.delete(b))

        await vm.commitEditSession()

        XCTAssertTrue(ocr.recognisedIDs.isEmpty)
        XCTAssertEqual(translator.translateCalls.count, 0)
        XCTAssertEqual(translator.batchCalls.count, 0)
        if case .translated(let bubbles) = vm.pages[0].state {
            XCTAssertTrue(bubbles.isEmpty)
        } else {
            XCTFail("Empty-set path should land in .translated([])")
        }
        XCTAssertNil(vm.editSession)
    }

    func testCommitPersistsIsManualThroughCacheRoundTrip() async {
        let drawnId = UUID()
        let existing = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "auto", observations: [], index: 0, isManual: false
        )
        let page = makeTranslatedPage(with: [existing])
        let cache = CapturingCacheService()
        let translator = RecordingTranslationService()
        let ocr = RecordingEditModeOCR(text: "drawn-text")
        let vm = makeEditVM(translation: translator, editOCR: ocr, cache: cache)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        let drawn = BubbleCluster(
            id: drawnId,
            boundingBox: CGRect(x: 80, y: 80, width: 30, height: 30),
            text: "", observations: [], isManual: true
        )
        vm.applyEditAction(.add(drawn))

        await vm.commitEditSession()

        XCTAssertEqual(cache.storedBubbleSets.count, 1)
        let storedBubbles = cache.storedBubbleSets.last ?? []
        let storedDrawn = storedBubbles.first(where: { $0.bubble.id == drawnId })
        XCTAssertEqual(storedDrawn?.bubble.isManual, true)
        let storedExisting = storedBubbles.first(where: { $0.bubble.id == existing.id })
        XCTAssertEqual(storedExisting?.bubble.isManual, false)
    }

    func testCommitSucceedsEvenWhenCacheStoreThrows() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let cache = CapturingCacheService()
        cache.storeError = CacheError.unavailable
        let translator = RecordingTranslationService()
        let ocr = RecordingEditModeOCR(text: "fresh")
        let vm = makeEditVM(translation: translator, editOCR: ocr, cache: cache)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Trigger an OCR-dirty edit so the commit path goes all the way
        // through cache store.
        let moved = CGRect(x: 10, y: 0, width: 20, height: 20)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: moved))

        await vm.commitEditSession()

        // In-memory commit succeeded.
        if case .translated = vm.pages[0].state {
            // ok
        } else {
            XCTFail("Cache failure must not roll back the in-memory commit")
        }
        XCTAssertNil(vm.editSession)
    }

    func testCommitCacheStoreFailureIsLoggedAsWarning() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let cache = CapturingCacheService()
        cache.storeError = CacheError.unavailable
        let logFixture = makeDebugLogFixture()
        defer { logFixture.cleanup() }
        let vm = makeEditVM(
            translation: RecordingTranslationService(),
            editOCR: RecordingEditModeOCR(text: "fresh"),
            cache: cache,
            pipelineLogger: logFixture.logger
        )
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        vm.applyEditAction(.move(
            id: b.id,
            from: b.boundingBox,
            to: CGRect(x: 10, y: 0, width: 20, height: 20)
        ))

        await vm.commitEditSession()
        await logFixture.logger.flush()

        var filter = DebugLogFilter()
        filter.category = .cache
        filter.sessionIDFilter = .session(logFixture.logger.sessionID)
        let entries = await logFixture.store.queryAll(filter: filter)
        let match = entries.first { $0.message.contains("CacheService.store [edit commit]") }
        XCTAssertEqual(match?.level, .warning)
    }

    // MARK: - Keyboard helpers (manual-bubble-editing change)

    func testEscapeCascadeWithSelectionClearsSelectionOnly() {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        vm.setSelection([b.id])

        vm.handleEscapeCascade()

        XCTAssertNotNil(vm.editSession, "Session must stay open")
        XCTAssertTrue(vm.editSession?.selectedBubbleIds.isEmpty ?? false)
    }

    func testEscapeCascadeWithEmptySelectionTriggersCancel() {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        XCTAssertNotNil(vm.editSession)

        vm.handleEscapeCascade()

        XCTAssertNil(vm.editSession, "Empty-selection Esc must trigger Cancel")
    }

    func testNudgeSelectionMovesAllSelectedBubblesAndRecordsSingleMultiUndo() {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 10, y: 10, width: 20, height: 20),
            text: "a", observations: [], index: 0
        )
        let b = BubbleCluster(
            boundingBox: CGRect(x: 60, y: 60, width: 20, height: 20),
            text: "b", observations: [], index: 1
        )
        let page = makeTranslatedPage(with: [a, b])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        vm.setSelection([a.id, b.id])

        vm.nudgeSelection(dx: 1, dy: 0)

        let working = vm.editSession?.workingBubbles ?? []
        XCTAssertEqual(working.first(where: { $0.id == a.id })?.boundingBox.origin.x, 11)
        XCTAssertEqual(working.first(where: { $0.id == b.id })?.boundingBox.origin.x, 61)
        // One undo entry covering both moves.
        XCTAssertEqual(vm.editSession?.undoStack.count, 1)
        if case .multi(let subs) = vm.editSession?.undoStack.last ?? .add(a) {
            XCTAssertEqual(subs.count, 2)
        } else {
            XCTFail("Two-box nudge must record a single .multi undo entry")
        }
    }

    func testNudgeSelectionWithEmptySelectionIsNoop() {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "a", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [a])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        XCTAssertTrue(vm.editSession?.selectedBubbleIds.isEmpty ?? false)

        vm.nudgeSelection(dx: -1, dy: 0)

        // Working copy and undo stack are untouched.
        XCTAssertEqual(vm.editSession?.workingBubbles.first?.boundingBox.origin.x, 0)
        XCTAssertTrue(vm.editSession?.undoStack.isEmpty ?? false)
    }

    func testNudgeSelectionClampsToImageBoundsAndSkipsNoop() {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "a", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [a])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        vm.setSelection([a.id])

        vm.nudgeSelection(dx: -10, dy: -10)

        XCTAssertEqual(vm.editSession?.workingBubbles.first?.boundingBox, a.boundingBox)
        XCTAssertTrue(vm.editSession?.undoStack.isEmpty ?? false)
    }

    func testSelectAllBubblesIncludesEveryNonDeletedBubble() {
        let a = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", observations: [], index: 0)
        let b = BubbleCluster(boundingBox: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b", observations: [], index: 1)
        let c = BubbleCluster(boundingBox: CGRect(x: 40, y: 0, width: 10, height: 10), text: "c", observations: [], index: 2)
        let page = makeTranslatedPage(with: [a, b, c])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        vm.applyEditAction(.delete(b))

        vm.selectAllBubbles()

        XCTAssertEqual(vm.editSession?.selectedBubbleIds, Set([a.id, c.id]))
    }

    func testCycleSelectionForwardFromEmptyPicksFirstByIndex() {
        let a = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", observations: [], index: 0)
        let b = BubbleCluster(boundingBox: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b", observations: [], index: 1)
        let page = makeTranslatedPage(with: [a, b])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        vm.cycleSelection(direction: 1)
        XCTAssertEqual(vm.editSession?.selectedBubbleIds, [a.id])

        vm.cycleSelection(direction: 1)
        XCTAssertEqual(vm.editSession?.selectedBubbleIds, [b.id])

        // Wrap around to the lowest index.
        vm.cycleSelection(direction: 1)
        XCTAssertEqual(vm.editSession?.selectedBubbleIds, [a.id])
    }

    func testStageDeleteSelectedEmitsMultiForGroupedDelete() {
        let a = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", observations: [], index: 0)
        let b = BubbleCluster(boundingBox: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b", observations: [], index: 1)
        let page = makeTranslatedPage(with: [a, b])
        let vm = makeEditVM()
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        vm.setSelection([a.id, b.id])

        vm.stageDeleteSelected()

        XCTAssertEqual(vm.editSession?.deletedBubbleIds, Set([a.id, b.id]))
        XCTAssertEqual(vm.editSession?.undoStack.count, 1)
        if case .multi(let subs) = vm.editSession?.undoStack.last ?? .add(a) {
            XCTAssertEqual(subs.count, 2)
        } else {
            XCTFail("Two-box delete must record a single .multi undo entry")
        }
    }

    func testPageNavigationMethodsAreIgnoredDuringEditSession() {
        let a = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", observations: [], index: 0)
        let first = makeTranslatedPage(with: [a])
        let second = makeTranslatedPage(with: [a])
        let vm = makeEditVM()
        vm.pages = [first, second]
        vm.currentPageIndex = 0
        vm.openEditSession(pageId: first.id)

        vm.nextPage()
        XCTAssertEqual(vm.currentPageIndex, 0)

        vm.currentPageIndex = 1
        vm.previousPage()
        XCTAssertEqual(vm.currentPageIndex, 1)
    }

    // MARK: - Re-translate preserves manual edits (manual-bubble-editing fix)

    func testRetranslatePreservesCommittedBubbleSetAndIsManualFlags() async {
        // Setup: a page translated with two bubbles — one auto, one manual.
        let drawnId = UUID()
        let autoId = UUID()
        let auto = BubbleCluster(
            id: autoId,
            boundingBox: CGRect(x: 0, y: 0, width: 40, height: 40),
            text: "auto-src",
            observations: [],
            index: 0,
            isManual: false
        )
        let drawn = BubbleCluster(
            id: drawnId,
            boundingBox: CGRect(x: 100, y: 100, width: 30, height: 30),
            text: "drawn-src",
            observations: [],
            index: 1,
            isManual: true
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/preserve-\(UUID().uuidString).jpg"))
        page.image = makeTestImage()
        page.imageHash = "preserve-\(UUID().uuidString)"
        page.state = .translated([
            TranslatedBubble(bubble: auto, translatedText: "T-auto", index: 0),
            TranslatedBubble(bubble: drawn, translatedText: "T-drawn", index: 1)
        ])

        // OCR fake fails loudly if called — proves Re-translate skipped detection.
        let assertNoOCRDetector = FailIfOCRCalledDetector()
        let assertNoOCRService = MangaOCRService(detector: assertNoOCRDetector)
        let router = OCRRouter(
            mangaOCRService: assertNoOCRService,
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { throw PaddleOCRError.modelUnavailable }
        )
        let translator = RecordingTranslationService()
        let prefs = makePrefs(source: .ja, target: .zhHant)
        let vm = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: translator
        )
        vm.pages = [page]

        await vm.translatePage(at: 0, mode: .retranslate)

        // OCR detector was never asked to detect.
        XCTAssertEqual(assertNoOCRDetector.detectCallCount, 0,
                       "Re-translate must skip OCR detection when the page already has committed bubbles")
        // Translator received the preserved bubble set with isManual intact.
        XCTAssertEqual(translator.translateCalls.count, 1)
        let received = translator.translateCalls.last?.bubbles ?? []
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first(where: { $0.id == autoId })?.isManual, false)
        XCTAssertEqual(received.first(where: { $0.id == drawnId })?.isManual, true)
        // Output page state retains those flags.
        if case .translated(let outputBubbles) = vm.pages[0].state {
            XCTAssertEqual(outputBubbles.first(where: { $0.bubble.id == drawnId })?.bubble.isManual, true)
            XCTAssertEqual(outputBubbles.first(where: { $0.bubble.id == autoId })?.bubble.isManual, false)
        } else {
            XCTFail("Re-translate should land in .translated")
        }
    }

    func testRetranslatePreservesCommittedOrderWhenBubbleIndicesAreStale() async {
        // Re-translate preserves the committed TranslatedBubble order, not a
        // stale BubbleCluster.index that may predate a manual sidebar reorder.
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "A", observations: [], index: 0
        )
        let b = BubbleCluster(
            boundingBox: CGRect(x: 30, y: 0, width: 20, height: 20),
            text: "B", observations: [], index: 1
        )
        let c = BubbleCluster(
            boundingBox: CGRect(x: 60, y: 0, width: 20, height: 20),
            text: "C", observations: [], index: 2
        )
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/preserve-order-\(UUID().uuidString).jpg"))
        page.image = makeTestImage()
        page.imageHash = "preserve-order-\(UUID().uuidString)"
        page.state = .translated([
            TranslatedBubble(bubble: c, translatedText: "T:C", index: 0),
            TranslatedBubble(bubble: a, translatedText: "T:A", index: 1),
            TranslatedBubble(bubble: b, translatedText: "T:B", index: 2)
        ])

        let translator = RecordingTranslationService()
        let vm = TranslationViewModel(
            preferences: makePrefs(source: .ja, target: .zhHant),
            ocrRouter: makeEmptyRouter(),
            translationService: translator
        )
        vm.pages = [page]

        await vm.translatePage(at: 0, mode: .retranslate)

        XCTAssertEqual(translator.translateCalls.last?.bubbles.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(translator.translateCalls.last?.bubbles.map(\.index), [0, 1, 2])
        guard case .translated(let result) = vm.pages[0].state else {
            return XCTFail("Re-translate should land in .translated")
        }
        XCTAssertEqual(result.map(\.bubble.id), [c.id, a.id, b.id])
        XCTAssertEqual(result.map(\.index), [0, 1, 2])
        XCTAssertEqual(result.map(\.bubble.index), [0, 1, 2])
    }

    func testIsCommittingEditSessionFlipsForTheDurationOfCommit() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let translator = RecordingTranslationService()
        let ocr = RecordingEditModeOCR(text: "fresh")
        let vm = makeEditVM(translation: translator, editOCR: ocr)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        XCTAssertFalse(vm.isCommittingEditSession)

        // Touch a bubble so commit reaches the translator.
        let moved = CGRect(x: 5, y: 0, width: 20, height: 20)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: moved))

        await vm.commitEditSession()

        XCTAssertFalse(vm.isCommittingEditSession,
                       "Flag must reset on the success path even after async work")
    }

    func testEditMutationsAreIgnoredWhileCommitIsInFlight() async {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "a", observations: [], index: 0
        )
        let b = BubbleCluster(
            boundingBox: CGRect(x: 40, y: 0, width: 20, height: 20),
            text: "b", observations: [], index: 1
        )
        let page = makeTranslatedPage(with: [a, b])
        let translator = BlockingTranslationService()
        let ocr = RecordingEditModeOCR(text: "fresh")
        let vm = makeEditVM(translation: translator, editOCR: ocr)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        let moved = CGRect(x: 5, y: 0, width: 20, height: 20)
        vm.applyEditAction(.move(id: a.id, from: a.boundingBox, to: moved))

        let task = Task { await vm.commitEditSession() }
        await translator.waitUntilTranslateStarted()
        XCTAssertTrue(vm.isCommittingEditSession)
        let snapshot = vm.editSession

        vm.applyEditAction(.delete(b))
        vm.undo()
        vm.redo()
        vm.setSelection([b.id])
        vm.selectAllBubbles()
        vm.cycleSelection(direction: 1)
        vm.stageDeleteSelected()
        vm.nudgeSelection(dx: 10, dy: 0)
        vm.handleEscapeCascade()

        XCTAssertEqual(vm.editSession?.workingBubbles.map(\.id), snapshot?.workingBubbles.map(\.id))
        XCTAssertEqual(vm.editSession?.workingBubbles.map(\.boundingBox), snapshot?.workingBubbles.map(\.boundingBox))
        XCTAssertEqual(vm.editSession?.deletedBubbleIds, snapshot?.deletedBubbleIds)
        XCTAssertEqual(vm.editSession?.selectedBubbleIds, snapshot?.selectedBubbleIds)
        XCTAssertEqual(vm.editSession?.undoStack.count, snapshot?.undoStack.count)
        XCTAssertEqual(vm.editSession?.redoStack.count, snapshot?.redoStack.count)

        await translator.release()
        await task.value
    }

    func testCommitFailureResetsCommittingFlag() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let translator = RecordingTranslationService(throwOnTranslate: SimulatedTranslateError.network)
        let ocr = RecordingEditModeOCR(text: "fresh")
        let vm = makeEditVM(translation: translator, editOCR: ocr)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)
        let moved = CGRect(x: 5, y: 0, width: 20, height: 20)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: moved))

        await vm.commitEditSession()

        // Session preserved (per failure semantics) and the flag is back to false
        // so the user can retry or cancel.
        XCTAssertNotNil(vm.editSession)
        XCTAssertFalse(vm.isCommittingEditSession)
    }

    func testCommitNeverInvokesTranslateBatch() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let translator = RecordingTranslationService()
        let ocr = RecordingEditModeOCR(text: "fresh")
        let vm = makeEditVM(translation: translator, editOCR: ocr)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Touch the bubble so commit reaches the translator.
        let moved = CGRect(x: 5, y: 0, width: 20, height: 20)
        vm.applyEditAction(.move(id: b.id, from: b.boundingBox, to: moved))

        await vm.commitEditSession()

        XCTAssertEqual(translator.batchCalls.count, 0)
        XCTAssertGreaterThanOrEqual(translator.translateCalls.count, 1)
    }

    func testRetranslateCurrentPageIsIgnoredDuringEditSession() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let translator = RecordingTranslationService()
        let vm = makeEditVM(translation: translator, editOCR: RecordingEditModeOCR(text: "fresh"))
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        await vm.retranslateCurrentPage()

        XCTAssertNotNil(vm.editSession)
        XCTAssertEqual(translator.translateCalls.count, 0)
        XCTAssertEqual(translator.batchCalls.count, 0)
        guard case .translated(let bubbles) = vm.pages[0].state else {
            return XCTFail("Expected page to remain translated during edit")
        }
        XCTAssertEqual(bubbles.map(\.bubble.id), [b.id])
    }

    func testRetranslateAllPagesIsIgnoredDuringEditSession() async {
        let a = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "a", observations: [], index: 0
        )
        let b = BubbleCluster(
            boundingBox: CGRect(x: 30, y: 0, width: 20, height: 20),
            text: "b", observations: [], index: 0
        )
        let translator = RecordingTranslationService()
        let vm = makeEditVM(translation: translator, editOCR: RecordingEditModeOCR(text: "fresh"))
        vm.pages = [makeTranslatedPage(with: [a]), makeTranslatedPage(with: [b])]
        vm.openEditSession(pageId: vm.pages[0].id)

        await vm.retranslateAllPages()

        XCTAssertNotNil(vm.editSession)
        XCTAssertEqual(translator.translateCalls.count, 0)
        XCTAssertEqual(translator.batchCalls.count, 0)
        guard case .translated(let pageOneBubbles) = vm.pages[0].state,
              case .translated(let pageTwoBubbles) = vm.pages[1].state else {
            return XCTFail("Expected pages to remain translated during edit")
        }
        XCTAssertEqual(pageOneBubbles.map(\.bubble.id), [a.id])
        XCTAssertEqual(pageTwoBubbles.map(\.bubble.id), [b.id])
    }

    func testHandleInputIsIgnoredDuringEditSession() async {
        let b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 20, height: 20),
            text: "x", observations: [], index: 0
        )
        let page = makeTranslatedPage(with: [b])
        let translator = RecordingTranslationService()
        let vm = makeEditVM(translation: translator, editOCR: RecordingEditModeOCR(text: "fresh"))
        vm.pages = [page]
        vm.sourcePath = "/tmp/original-source"
        vm.openEditSession(pageId: vm.pages[0].id)

        await vm.handleInput(URL(fileURLWithPath: "/tmp/new-input-\(UUID().uuidString).jpg"))

        XCTAssertNotNil(vm.editSession)
        XCTAssertEqual(vm.sourcePath, "/tmp/original-source")
        XCTAssertEqual(vm.pages.map(\.id), [page.id])
        XCTAssertEqual(translator.translateCalls.count, 0)
        XCTAssertEqual(translator.batchCalls.count, 0)
    }

    private func makeEditVM(
        translation: any TranslationService,
        editOCR: any EditModeOCRPerforming,
        cache: (any CacheServiceProtocol)? = nil,
        pipelineLogger: any PipelineLogging = DebugLogger.shared
    ) -> TranslationViewModel {
        let prefs = makePrefs(source: .ja, target: .zhHant)
        return TranslationViewModel(
            preferences: prefs,
            ocrRouter: makeEmptyRouter(),
            translationService: translation,
            cacheService: cache,
            pipelineLogger: pipelineLogger,
            editModeOCR: editOCR
        )
    }
}

// MARK: - Edit Mode test doubles

private enum SimulatedTranslateError: Error {
    case network
}

@MainActor
private final class RecordingEditModeOCR: EditModeOCRPerforming {
    struct Call {
        let bubbles: [BubbleCluster]
    }
    private let textProvider: (BubbleCluster) -> String
    private(set) var calls: [Call] = []
    var recognisedIDs: [UUID] { calls.flatMap { $0.bubbles.map(\.id) } }

    init(text: String) {
        self.textProvider = { _ in text }
    }
    init(textProvider: @escaping (BubbleCluster) -> String) {
        self.textProvider = textProvider
    }

    func recognizeRegions(
        image: NSImage,
        bubbles: [BubbleCluster],
        sourceLanguage: Language
    ) async throws -> [UUID: String] {
        calls.append(Call(bubbles: bubbles))
        var output: [UUID: String] = [:]
        for b in bubbles { output[b.id] = textProvider(b) }
        return output
    }
}

private final class RecordingTranslationService: TranslationService, @unchecked Sendable {
    struct TranslateCall {
        let bubbles: [BubbleCluster]
        let context: TranslationContext
    }
    struct BatchCall {
        let pageInputs: [BatchPageInput]
    }
    var engine: TranslationEngine { .githubCopilot }
    private(set) var translateCalls: [TranslateCall] = []
    private(set) var batchCalls: [BatchCall] = []
    private let throwOnTranslate: Error?

    init(throwOnTranslate: Error? = nil) {
        self.throwOnTranslate = throwOnTranslate
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        translateCalls.append(TranslateCall(bubbles: bubbles, context: context))
        if let err = throwOnTranslate { throw err }
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
        batchCalls.append(BatchCall(pageInputs: pageInputs))
        return pageInputs.map { input in
            BatchPageOutput(
                pageId: input.pageId,
                bubbles: input.bubbles.map {
                    TranslatedBubble(bubble: $0, translatedText: "B:\($0.text)", index: $0.index)
                },
                detectedTerms: []
            )
        }
    }
}

private final class BlockingTranslationService: TranslationService, @unchecked Sendable {
    var engine: TranslationEngine { .githubCopilot }
    private let gate = BlockingTranslationGate()

    func waitUntilTranslateStarted() async {
        await gate.waitUntilTranslateStarted()
    }

    func release() async {
        await gate.release()
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        await gate.waitForRelease()
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
        []
    }
}

private actor BlockingTranslationGate {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func waitUntilTranslateStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                startContinuations.append(continuation)
            }
        }
    }

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            didStart = true
            let continuations = startContinuations
            startContinuations = []
            continuations.forEach { $0.resume() }
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class CapturingCacheService: CacheServiceProtocol, @unchecked Sendable {
    var isAvailable: Bool = true
    var storeError: Error?
    let glossaryService: GlossaryService = GlossaryService(db: nil, isAvailable: false)
    private(set) var storedBubbleSets: [[TranslatedBubble]] = []

    func lookup(
        imageHash: String, source: Language, target: Language, engine: TranslationEngine
    ) -> CacheService.CachedTranslationResult? { nil }
    func translationCacheSize() -> Int64 { 0 }

    func store(
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine,
        bubbles: [TranslatedBubble]
    ) throws {
        if let storeError { throw storeError }
        storedBubbleSets.append(bubbles)
    }

    func clearAll() throws {}
}

// MARK: - Helpers

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

// Detector whose `detectCallCount` lets tests assert OCR detection was
// skipped (e.g. the Re-translate preservation path must not re-detect).
// Returns an empty region set so it is safe to leave wired even when the
// pipeline accidentally calls it; the call count is the assertion target.
private final class FailIfOCRCalledDetector: ComicTextDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _detectCallCount = 0
    var detectCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _detectCallCount
    }
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        lock.lock()
        _detectCallCount += 1
        lock.unlock()
        return ComicTextDetectorResult(regions: [], textPixelMask: nil, lowConfidenceRegionCount: 0)
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

private final class SuspendingTranslationService: @unchecked Sendable, TranslationService {
    var engine: TranslationEngine { .githubCopilot }
    private let lock = NSLock()
    private var _translateCallCount = 0
    var translateCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _translateCallCount
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        lock.lock()
        _translateCallCount += 1
        lock.unlock()
        while true {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
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
    var clearAllError: Error?
    private(set) var storeCallCount = 0
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
        bubbles: [TranslatedBubble]
    ) throws {
        storeCallCount += 1
        if let storeError { throw storeError }
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
// Wraps SizeMappedOCRRecognizer with a fixed per-call latency so tests can
// assert what has — and has not — happened while OCR for later pages is still
// running. `recognizeText` is synchronous by protocol, so the delay blocks the
// OCR actor's thread; keep delays short (the OCR actor is the only blocked
// executor, and the suite budget absorbs sub-second sleeps).
private final class DelayingSizeMappedOCRRecognizer: @unchecked Sendable, OCRRecognizing {
    let inner: SizeMappedOCRRecognizer
    private let delay: TimeInterval

    init(textByWidth: [Int: String], delay: TimeInterval) {
        self.inner = SizeMappedOCRRecognizer(textByWidth: textByWidth)
        self.delay = delay
    }

    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        Thread.sleep(forTimeInterval: delay)
        return try inner.recognizeText(in: cgImage, region: region)
    }
}

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
    private var _batchCalls: [(pageIds: [String], summaries: [String], glossarySources: [String])] = []
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

    var batchCalls: [(pageIds: [String], summaries: [String], glossarySources: [String])] {
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
        lock.withLock {
            _batchCalls.append((
                pageIds: pageIds,
                summaries: priorContext.recentPageSummaries,
                glossarySources: priorContext.glossaryTerms.map { $0.sourceTerm }
            ))
        }

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

// UniqueTextRecognizer with a fixed per-call latency, for cancellation tests
// that need preparations still in flight at the cancel point. The delay blocks
// the OCR actor's thread (the protocol is synchronous); keep it short.
private final class DelayingUniqueTextRecognizer: @unchecked Sendable, OCRRecognizing {
    private let inner = UniqueTextRecognizer()
    private let delay: TimeInterval
    init(delay: TimeInterval) { self.delay = delay }
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        Thread.sleep(forTimeInterval: delay)
        return try inner.recognizeText(in: cgImage, region: region)
    }
}

@MainActor
private func makeBatchSchedulerFixture(
    bubbleCountsByPage: [Int],
    engine: TranslationEngine = .githubCopilot,
    recognizer: (any OCRRecognizing)? = nil
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
    await mocService.setRecognizer(recognizer ?? UniqueTextRecognizer())
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

    // The batch shares one system prompt across all pages, so a glossary term
    // appearing in ANY page of the batch must survive filtering — while terms
    // appearing in no page of the batch must be dropped. Ramp groups for three
    // 1-bubble pages: [0], [1, 2]; the term lives on the second batch's
    // second page.
    func testBatchContextKeepsGlossaryTermsFromAnyPageInBatch() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [1, 1, 1]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Page index 0 OCRs as "w300b0", index 1 as "w301b0", index 2 as "w302b0".
        let glossary = try XCTUnwrap(try? vm.glossaryServiceForView.createGlossary(name: "Names"))
        _ = try? vm.glossaryServiceForView.addTerm(
            glossaryID: glossary.id, sourceTerm: "w302b0", targetTerm: "P3", autoDetected: false
        )
        _ = try? vm.glossaryServiceForView.addTerm(
            glossaryID: glossary.id, sourceTerm: "absent", targetTerm: "X", autoDetected: true
        )
        vm.loadGlossaries()
        vm.activeGlossaryID = glossary.id

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 2)
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1", "2"])
        XCTAssertEqual(
            service.batchCalls[1].glossarySources,
            ["w302b0"],
            "Term from the batch's second page must be kept; term absent from every page must be dropped"
        )
    }

    // producer-consumer-llm-pipeline: group caps ramp 1, 3, 5 and hold at 5.
    // The first group ships after page 1's preparation alone (first-page latency),
    // the ramp bounds the extra LLM calls to at most 2 per run versus full-cap
    // grouping, and composition depends only on counts — never OCR/LLM timing.
    func testRunBatchPipelineRampUpGroupCapsAndHoldsAtFive() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: Array(repeating: 4, count: 12)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 4)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1", "2", "3"])
        XCTAssertEqual(service.batchCalls[2].pageIds, ["4", "5", "6", "7", "8"])
        XCTAssertEqual(service.batchCalls[3].pageIds, ["9", "10", "11"])
        XCTAssertEqual(service.perPageCalls.count, 0)
    }

    // 6.1 (ramp caps 1, 3, 5: five low-bubble pages split [0], [1,2,3], [4])
    func testRunBatchPipelineGroupsFiveLowBubblePagesUnderRampCaps() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [8, 8, 8, 8, 8]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 3)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1", "2", "3"])
        XCTAssertEqual(service.batchCalls[2].pageIds, ["4"])
        XCTAssertEqual(service.perPageCalls.count, 0)
    }

    // 6.2 ([20, 20, 20, 5, 5]: group 2 fits exactly 45 bubbles (20+20+5) at
    // the ramp cap of 3, leaving [4] for group 3)
    func testRunBatchPipelineFlushesOnBubbleThreshold() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [20, 20, 20, 5, 5]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 3)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1", "2", "3"])
        XCTAssertEqual(service.batchCalls[2].pageIds, ["4"])
    }

    // 6.3 (ramp: [0], [1,2,3], then the page cap holds the last group at 4)
    func testRunBatchPipelineFlushesOnPageCap() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4, 4, 4, 4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        await vm.loadFolder(root)

        XCTAssertEqual(service.batchCalls.count, 3)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1", "2", "3"])
        XCTAssertEqual(service.batchCalls[2].pageIds, ["4", "5", "6", "7"])
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
            bubbles: [cachedBubble]
        )

        await vm.loadFolder(root)

        // Ramp + cache-hit boundary: [0] (cap 1), [1] (cap 3, cut short by the
        // cached page 2), then [3, 4]. The cached page never enters a batch
        // and does not consume a ramp slot.
        XCTAssertEqual(service.batchCalls.count, 3)
        XCTAssertEqual(service.batchCalls[0].pageIds, ["0"])
        XCTAssertEqual(service.batchCalls[1].pageIds, ["1"])
        XCTAssertEqual(service.batchCalls[2].pageIds, ["3", "4"])
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
            bubbles: [cachedBubble]
        )

        await vm.loadFolder(root)

        // Ramp + cache-hit boundary: [0], [1], then [3, 4]. The last batch's
        // priorContext is sampled after pages 0 and 1 finalized and the cache
        // hit (page 2) contributed its cached text to the rolling window.
        XCTAssertEqual(service.batchCalls.count, 3)
        let lastBatchSummaries = service.batchCalls[2].summaries
        XCTAssertTrue(
            lastBatchSummaries.contains(where: { $0.contains("cached-text") }),
            "Last batch's priorContext must contain page 2's cached translated text — got \(lastBatchSummaries)"
        )
    }

    // 6.7
    func testRunBatchPipelineBatchFailureFallsBackToPerPageInPageIndexOrder() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 20, 20, 5]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Ramp groups for [4,4,20,20,5]: [0] (cap 1), [1,2,3] (4+20+20 = 44 ≤ 45
        // at cap 3), [4]. Fail the second group's batch call.
        service.failBatchForPageIds = ["1"]

        await vm.loadFolder(root)

        // The fallback path uses the per-page translate(...) for each page in the failed group.
        let perPageInputs = service.perPageCalls.map { $0.input }
        XCTAssertEqual(perPageInputs.count, 3, "Pages 1, 2, 3 must fall back to per-page (got \(perPageInputs))")
        // Page-index order. Bubble text is "w<width>b<idx>"; widths are 301..303.
        XCTAssertTrue(perPageInputs[0].hasPrefix("w301"), "First per-page call must be for page 1 (got \(perPageInputs[0]))")
        XCTAssertTrue(perPageInputs[1].hasPrefix("w302"), "Second per-page call must be for page 2 (got \(perPageInputs[1]))")
        XCTAssertTrue(perPageInputs[2].hasPrefix("w303"), "Third per-page call must be for page 3 (got \(perPageInputs[2]))")
    }

    // 6.8
    func testRunBatchPipelineBatchFailureFallbackPreservesRecentContext() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 20, 20, 5]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Ramp groups: [0], [1,2,3] (fails twice → per-page fallback), [4].
        service.failBatchForPageIds = ["1"]

        await vm.loadFolder(root)

        // The window grows between per-page fallback calls: page 1 sees page 0's
        // summary; page 2 sees pages 0-1; page 3 sees pages 0-2.
        XCTAssertEqual(service.perPageCalls.count, 3)
        XCTAssertEqual(service.perPageCalls[0].summaries.count, 1,
                       "Page 1 must see 1 prior summary — got \(service.perPageCalls[0].summaries)")
        XCTAssertEqual(service.perPageCalls[1].summaries.count, 2,
                       "Page 2 must see 2 prior summaries — got \(service.perPageCalls[1].summaries)")
        XCTAssertEqual(service.perPageCalls[2].summaries.count, 3,
                       "Page 3 must see 3 prior summaries — got \(service.perPageCalls[2].summaries)")
        // Each successful fallback page contributes to the next call's window.
        XCTAssertNotEqual(service.perPageCalls[1].summaries, service.perPageCalls[2].summaries,
                          "Window must shift as fallback pages succeed")
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

    // producer-consumer-llm-pipeline: cancel while preparations are still in
    // flight. Batch [0] suspends until cancel; with ~80ms OCR per page, later
    // pages are mid-preparation or unstarted at the cancel point. The
    // post-quiescence sweep must return every non-finalized page to .pending
    // and no late preparation result may overwrite that.
    func testRunBatchPipelineCancelRevertsPagesStillInPreparation() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [1, 1, 1, 1, 1, 1],
            recognizer: DelayingUniqueTextRecognizer(delay: 0.08)
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

        XCTAssertEqual(service.batchCalls.count, 1, "No later batch must dispatch after cancel")
        XCTAssertEqual(service.perPageCalls.count, 0, "Cancellation must not trigger per-page fallback")
        for i in vm.pages.indices {
            if case .pending = vm.pages[i].state { continue }
            XCTFail("Page \(i) must return to .pending after cancel, got \(vm.pages[i].state)")
        }
        XCTAssertFalse(vm.isProcessing, "isProcessing must clear after the scheduler exits")
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

    func testCancelBatchCancelsViewModelOwnedRetranslateTask() async throws {
        let (root, service, vm, _) = try await makeBatchSchedulerFixture(
            bubbleCountsByPage: [4, 4, 4]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let pageURLs = (1...3).map { root.appendingPathComponent("page_\($0).png") }
        vm.pages = pageURLs.map { url in
            var page = MangaPage(imageURL: url)
            page.image = NSImage(contentsOf: url)
            return page
        }
        service.suspendBatchUntilCancel = true

        let task = try XCTUnwrap(vm.startRetranslateAllPages())
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if service.batchCalls.count >= 1 { break }
        }

        XCTAssertTrue(vm.canCancelTranslation, "The toolbar must have a live cancel action while a ViewModel-owned batch is running")
        vm.cancelTranslation()
        await task.value

        XCTAssertEqual(service.batchCalls.count, 1, "The user cancel action must cancel the in-flight batch task")
        XCTAssertFalse(vm.isProcessing, "isProcessing must clear after the owned batch task exits")
        for i in vm.pages.indices {
            if case .pending = vm.pages[i].state { continue }
            XCTFail("Page \(i) must return to .pending after UI-driven cancel, got \(vm.pages[i].state)")
        }
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

        await vm.translatePage(at: 0, mode: .retranslate)

        XCTAssertEqual(service.batchCalls.count, 0, "Single-page entry must not call translateBatch")
        XCTAssertEqual(service.perPageCalls.count, 1, "Single-page entry must call translate exactly once")
    }
}
