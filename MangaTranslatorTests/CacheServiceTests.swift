import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator
import SQLite3

final class CacheServiceTests: XCTestCase {
    // MARK: - Existing happy-path tests, migrated to throws API

    func testLookupRoundTripsBubblePolarityAndMask() throws {
        let cache = makeCache()
        try cache.clearAll()

        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 10, y: 20, width: 30, height: 40),
            text: "hello",
            observations: [],
            index: 7,
            isInverted: true
        )
        let translated = TranslatedBubble(bubble: bubble, translatedText: "hola", index: 7)
        let mask = makeTestCGImage()
        let hash = "cache-test-\(UUID().uuidString)"

        try cache.store(
            imageHash: hash,
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [translated],
            textPixelMask: mask
        )

        let result = cache.lookup(imageHash: hash, source: .ja, target: .zhHant, engine: .githubCopilot)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bubbles.first?.bubble.isInverted, true)
        XCTAssertEqual(result?.bubbles.first?.bubble.text, "hello")
        XCTAssertNotNil(result?.textPixelMask)
    }

    func testClearAllRemovesPreviouslyCachedTranslations() throws {
        let cache = makeCache()
        try cache.clearAll()

        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4),
            text: "cached",
            observations: [],
            index: 0
        )
        let translated = TranslatedBubble(bubble: bubble, translatedText: "快取", index: 0)
        let hash = "clear-cache-\(UUID().uuidString)"

        try cache.store(
            imageHash: hash,
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [translated],
            textPixelMask: nil
        )
        XCTAssertNotNil(cache.lookup(imageHash: hash, source: .ja, target: .zhHant, engine: .githubCopilot))

        try cache.clearAll()

        XCTAssertNil(cache.lookup(imageHash: hash, source: .ja, target: .zhHant, engine: .githubCopilot))
    }

    func testGlossaryCRUDRoundTripsTermsAndDeleteRemovesTerms() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "Characters")

        let term = try service.addTerm(
            glossaryID: glossary.id,
            sourceTerm: "太郎",
            targetTerm: "Taro",
            autoDetected: false
        )

        try service.updateTerm(id: term.id, sourceTerm: "太郎", targetTerm: "Taro-sama")

        let updatedTerms = service.listTerms(glossaryID: glossary.id)
        XCTAssertEqual(updatedTerms.count, 1)
        XCTAssertEqual(updatedTerms[0].targetTerm, "Taro-sama")
        XCTAssertFalse(updatedTerms[0].autoDetected)

        try service.deleteGlossary(id: glossary.id)

        XCTAssertFalse(service.listGlossaries().contains { $0.id == glossary.id })
        XCTAssertTrue(service.listTerms(glossaryID: glossary.id).isEmpty)
    }

    func testDeleteGlossaryTreatsIDAsDataNotSQL() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "Safe glossary")
        _ = try service.addTerm(
            glossaryID: glossary.id,
            sourceTerm: "守る",
            targetTerm: "protect",
            autoDetected: true
        )

        try service.deleteGlossary(id: "' OR 1=1 --")

        XCTAssertTrue(service.listGlossaries().contains { $0.id == glossary.id })
        XCTAssertEqual(service.listTerms(glossaryID: glossary.id).count, 1)
    }

    func testInsertDetectedTermsDoesNotDuplicateExistingSourceTerms() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "Detected")
        _ = try service.addTerm(
            glossaryID: glossary.id,
            sourceTerm: "花子",
            targetTerm: "Hanako",
            autoDetected: false
        )

        try service.insertDetectedTerms([
            GlossaryTerm(id: "detected-1", sourceTerm: "花子", targetTerm: "Hanako alt", autoDetected: true),
            GlossaryTerm(id: "detected-2", sourceTerm: "学校", targetTerm: "school", autoDetected: true)
        ], glossaryID: glossary.id)

        let terms = service.listTerms(glossaryID: glossary.id)
        XCTAssertEqual(terms.filter { $0.sourceTerm == "花子" }.count, 1)
        XCTAssertTrue(terms.contains { $0.sourceTerm == "学校" && $0.autoDetected })
    }

    // MARK: - 1. CacheService availability + mutation throws

    // 1.1 Open failure → service unavailable, mutations throw, reads degrade.
    func testOpenFailureMakesServiceUnavailable() {
        let unwritablePath = "/nonexistent-\(UUID().uuidString)/dir/cache.sqlite"
        let cache = CacheService(databasePath: unwritablePath)

        XCTAssertFalse(cache.isAvailable)
        XCTAssertThrowsError(try cache.clearAll()) { error in
            XCTAssertEqual(error as? CacheError, .unavailable)
        }
        let lookup = cache.lookup(imageHash: "x", source: .ja, target: .zhHant, engine: .githubCopilot)
        XCTAssertNil(lookup)
    }

    // 1.2 PRAGMA failure → handle closed, isAvailable false, mutations throw unavailable.
    func testPragmaFailureMakesServiceUnavailable() {
        let path = tempDatabasePath()
        let cache = CacheService(databasePath: path, pragmaResultOverride: SQLITE_ERROR)

        XCTAssertFalse(cache.isAvailable)
        XCTAssertThrowsError(try cache.clearAll()) { error in
            XCTAssertEqual(error as? CacheError, .unavailable)
        }
        // The init must close the underlying handle on PRAGMA failure. We verify
        // by opening an exclusive lock on the same file — if the handle leaked,
        // SQLite would still hold a shared lock and an exclusive open would race.
        // Instead, simply ensure the file path is still usable from a new connection.
        var probe: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &probe), SQLITE_OK)
        sqlite3_close(probe)
    }

    // 1.3 clearAll failure surfaces a CacheError carrying code + message.
    func testClearAllFailureDoesNotReportSuccess() throws {
        let cache = makeCache()
        // Seed one row so the BEFORE DELETE trigger can fire (the trigger
        // is per-row; an empty table would otherwise leave the DELETE successful).
        let translated = TranslatedBubble(
            bubble: BubbleCluster(boundingBox: .zero, text: "t", observations: []),
            translatedText: "T",
            index: 0
        )
        try cache.store(
            imageHash: "h-\(UUID().uuidString)",
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [translated],
            textPixelMask: nil
        )
        let triggerResult = cache._executeSQL("""
            CREATE TRIGGER reject_translation_cache_delete
            BEFORE DELETE ON translation_cache
            BEGIN
                SELECT RAISE(FAIL, 'denied');
            END;
            """)
        XCTAssertEqual(triggerResult, SQLITE_OK)

        XCTAssertThrowsError(try cache.clearAll()) { error in
            guard case .sqlite(let code, let message, let operation) = error as? CacheError else {
                return XCTFail("Expected .sqlite error, got \(error)")
            }
            XCTAssertNotEqual(code, SQLITE_OK)
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(operation, "CacheService.clearAll")
        }
    }

    // 1.4 Regression guard: clearAll happy path still removes rows under throws.
    func testClearAllSuccessRemovesAllCachedRows() throws {
        let cache = makeCache()
        let hashA = "hash-a-\(UUID().uuidString)"
        let hashB = "hash-b-\(UUID().uuidString)"
        let translated = TranslatedBubble(
            bubble: BubbleCluster(boundingBox: .zero, text: "t", observations: []),
            translatedText: "T",
            index: 0
        )
        try cache.store(imageHash: hashA, source: .ja, target: .zhHant, engine: .githubCopilot, bubbles: [translated], textPixelMask: nil)
        try cache.store(imageHash: hashB, source: .ja, target: .zhHant, engine: .githubCopilot, bubbles: [translated], textPixelMask: nil)

        try cache.clearAll()

        XCTAssertNil(cache.lookup(imageHash: hashA, source: .ja, target: .zhHant, engine: .githubCopilot))
        XCTAssertNil(cache.lookup(imageHash: hashB, source: .ja, target: .zhHant, engine: .githubCopilot))
    }

    // 1.5 store failure throws CacheError with code + message.
    func testStoreFailureThrowsCacheError() throws {
        let cache = makeCache()
        let triggerResult = cache._executeSQL("""
            CREATE TRIGGER reject_translation_cache_insert
            BEFORE INSERT ON translation_cache
            BEGIN
                SELECT RAISE(FAIL, 'denied');
            END;
            """)
        XCTAssertEqual(triggerResult, SQLITE_OK)

        let translated = TranslatedBubble(
            bubble: BubbleCluster(boundingBox: .zero, text: "t", observations: []),
            translatedText: "T",
            index: 0
        )
        XCTAssertThrowsError(try cache.store(
            imageHash: "x",
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [translated],
            textPixelMask: nil
        )) { error in
            guard case .sqlite(let code, let message, _) = error as? CacheError else {
                return XCTFail("Expected .sqlite error, got \(error)")
            }
            XCTAssertNotEqual(code, SQLITE_OK)
            XCTAssertFalse(message.isEmpty)
        }
    }

    // 1.6 addHistory failure throws CacheError with code + message.
    func testAddHistoryFailureThrowsCacheError() throws {
        let cache = makeCache()
        let triggerResult = cache._executeSQL("""
            CREATE TRIGGER reject_history_insert
            BEFORE INSERT ON history
            BEGIN
                SELECT RAISE(FAIL, 'denied');
            END;
            """)
        XCTAssertEqual(triggerResult, SQLITE_OK)

        XCTAssertThrowsError(try cache.addHistory(path: "/tmp/x", pageCount: 2)) { error in
            guard case .sqlite(let code, let message, _) = error as? CacheError else {
                return XCTFail("Expected .sqlite error, got \(error)")
            }
            XCTAssertNotEqual(code, SQLITE_OK)
            XCTAssertFalse(message.isEmpty)
        }
    }

    // 1.7 PRAGMA foreign_keys is enabled after a successful open.
    func testForeignKeysAreEnabledAfterOpen() {
        let cache = makeCache()
        XCTAssertTrue(cache.isAvailable)
        XCTAssertEqual(cache._foreignKeysSetting(), 1)
    }

    // 1.8 lookup on unavailable cache returns nil and does not throw.
    func testLookupOnUnavailableCacheReturnsNil() {
        let cache = CacheService(databasePath: "/nonexistent-\(UUID().uuidString)/cache.sqlite")
        XCTAssertFalse(cache.isAvailable)
        let result = cache.lookup(imageHash: "x", source: .ja, target: .zhHant, engine: .githubCopilot)
        XCTAssertNil(result)
    }

    // 1.9 translationCacheSize on unavailable cache returns 0.
    func testTranslationCacheSizeOnUnavailableCacheReturnsZero() {
        let cache = CacheService(databasePath: "/nonexistent-\(UUID().uuidString)/cache.sqlite")
        XCTAssertFalse(cache.isAvailable)
        XCTAssertEqual(cache.translationCacheSize(), 0)
    }

    // 1.10 listGlossaries on unavailable cache returns [] without throwing.
    func testListGlossariesOnUnavailableCacheReturnsEmpty() {
        let cache = CacheService(databasePath: "/nonexistent-\(UUID().uuidString)/cache.sqlite")
        XCTAssertFalse(cache.isAvailable)
        XCTAssertTrue(cache.glossaryService.listGlossaries().isEmpty)
    }

    // MARK: - 2. GlossaryService atomicity

    // 2.1 Regression guard: delete success removes glossary AND terms.
    func testDeleteGlossarySucceedsRemovesGlossaryAndTerms() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "Atomic")
        _ = try service.addTerm(glossaryID: glossary.id, sourceTerm: "a", targetTerm: "A", autoDetected: false)
        _ = try service.addTerm(glossaryID: glossary.id, sourceTerm: "b", targetTerm: "B", autoDetected: false)

        try service.deleteGlossary(id: glossary.id)

        XCTAssertFalse(service.listGlossaries().contains { $0.id == glossary.id })
        XCTAssertTrue(service.listTerms(glossaryID: glossary.id).isEmpty)
    }

    // 2.2 Terms-delete failure → rollback restores both glossary and terms.
    func testDeleteGlossaryRollsBackWhenTermsDeleteFails() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "RollbackTerms")
        _ = try service.addTerm(glossaryID: glossary.id, sourceTerm: "a", targetTerm: "A", autoDetected: false)
        _ = try service.addTerm(glossaryID: glossary.id, sourceTerm: "b", targetTerm: "B", autoDetected: false)

        let triggerResult = cache._executeSQL("""
            CREATE TRIGGER reject_terms_delete
            BEFORE DELETE ON glossary_terms
            BEGIN
                SELECT RAISE(FAIL, 'denied');
            END;
            """)
        XCTAssertEqual(triggerResult, SQLITE_OK)

        XCTAssertThrowsError(try service.deleteGlossary(id: glossary.id))

        XCTAssertTrue(service.listGlossaries().contains { $0.id == glossary.id })
        XCTAssertEqual(service.listTerms(glossaryID: glossary.id).count, 2)
    }

    // 2.3 Glossary-delete failure (after terms delete succeeded) → rollback restores terms.
    func testDeleteGlossaryRollsBackWhenGlossaryDeleteFails() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "RollbackGlossary")
        _ = try service.addTerm(glossaryID: glossary.id, sourceTerm: "a", targetTerm: "A", autoDetected: false)
        _ = try service.addTerm(glossaryID: glossary.id, sourceTerm: "b", targetTerm: "B", autoDetected: false)

        let triggerResult = cache._executeSQL("""
            CREATE TRIGGER reject_glossary_delete
            BEFORE DELETE ON glossaries
            BEGIN
                SELECT RAISE(FAIL, 'denied');
            END;
            """)
        XCTAssertEqual(triggerResult, SQLITE_OK)

        XCTAssertThrowsError(try service.deleteGlossary(id: glossary.id))

        XCTAssertTrue(service.listGlossaries().contains { $0.id == glossary.id })
        XCTAssertEqual(service.listTerms(glossaryID: glossary.id).count, 2)
    }

    // 2.4 deleteGlossary on unavailable cache throws .unavailable.
    func testDeleteGlossaryOnUnavailableCacheThrowsUnavailable() {
        let cache = CacheService(databasePath: "/nonexistent-\(UUID().uuidString)/cache.sqlite")
        XCTAssertFalse(cache.isAvailable)
        XCTAssertThrowsError(try cache.glossaryService.deleteGlossary(id: "anything")) { error in
            XCTAssertEqual(error as? CacheError, .unavailable)
        }
    }

    // 2.5 addTerm INSERT failure throws CacheError with code + message.
    func testGlossaryAddTermFailureThrows() throws {
        let cache = makeCache()
        let service = cache.glossaryService
        let glossary = try service.createGlossary(name: "RejectInsert")

        let triggerResult = cache._executeSQL("""
            CREATE TRIGGER reject_term_insert
            BEFORE INSERT ON glossary_terms
            BEGIN
                SELECT RAISE(FAIL, 'denied');
            END;
            """)
        XCTAssertEqual(triggerResult, SQLITE_OK)

        XCTAssertThrowsError(try service.addTerm(
            glossaryID: glossary.id,
            sourceTerm: "a",
            targetTerm: "A",
            autoDetected: false
        )) { error in
            guard case .sqlite(let code, let message, _) = error as? CacheError else {
                return XCTFail("Expected .sqlite error, got \(error)")
            }
            XCTAssertNotEqual(code, SQLITE_OK)
            XCTAssertFalse(message.isEmpty)
        }
    }

    // 2.6 Foreign-key violation → addTerm throws.
    func testGlossaryAddTermViolatingForeignKeyThrows() throws {
        let cache = makeCache()
        XCTAssertEqual(cache._foreignKeysSetting(), 1)

        let nonexistentGlossaryID = UUID().uuidString
        XCTAssertThrowsError(try cache.glossaryService.addTerm(
            glossaryID: nonexistentGlossaryID,
            sourceTerm: "orphan",
            targetTerm: "Orphan",
            autoDetected: false
        )) { error in
            guard case .sqlite = error as? CacheError else {
                return XCTFail("Expected .sqlite error, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func makeCache() -> CacheService {
        return CacheService(databasePath: tempDatabasePath())
    }

    private func tempDatabasePath() -> String {
        return NSTemporaryDirectory() + "cache-test-\(UUID().uuidString).sqlite"
    }
}

private func makeTestCGImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8, space: colorSpace, bitmapInfo: 0)!
    return context.makeImage()!
}
