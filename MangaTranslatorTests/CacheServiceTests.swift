import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

final class CacheServiceTests: XCTestCase {
    func testLookupRoundTripsBubblePolarityAndMask() {
        let cache = CacheService()
        cache.clearAll()

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

        cache.store(
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

    func testClearAllRemovesPreviouslyCachedTranslations() {
        let cache = CacheService()
        cache.clearAll()

        let bubble = BubbleCluster(
            boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4),
            text: "cached",
            observations: [],
            index: 0
        )
        let translated = TranslatedBubble(bubble: bubble, translatedText: "快取", index: 0)
        let hash = "clear-cache-\(UUID().uuidString)"

        cache.store(
            imageHash: hash,
            source: .ja,
            target: .zhHant,
            engine: .githubCopilot,
            bubbles: [translated],
            textPixelMask: nil
        )
        XCTAssertNotNil(cache.lookup(imageHash: hash, source: .ja, target: .zhHant, engine: .githubCopilot))

        cache.clearAll()

        XCTAssertNil(cache.lookup(imageHash: hash, source: .ja, target: .zhHant, engine: .githubCopilot))
    }

    func testGlossaryCRUDRoundTripsTermsAndDeleteRemovesTerms() {
        let cache = CacheService()
        let service = cache.glossaryService
        let glossary = service.createGlossary(name: "Characters")
        XCTAssertNotNil(glossary)

        let term = service.insertTerm(
            glossaryID: glossary!.id,
            sourceTerm: "太郎",
            targetTerm: "Taro",
            autoDetected: false
        )
        XCTAssertNotNil(term)

        service.updateTerm(id: term!.id, sourceTerm: "太郎", targetTerm: "Taro-sama")

        let updatedTerms = service.listTerms(glossaryID: glossary!.id)
        XCTAssertEqual(updatedTerms.count, 1)
        XCTAssertEqual(updatedTerms[0].targetTerm, "Taro-sama")
        XCTAssertFalse(updatedTerms[0].autoDetected)

        service.deleteGlossary(id: glossary!.id)

        XCTAssertFalse(service.listGlossaries().contains { $0.id == glossary!.id })
        XCTAssertTrue(service.listTerms(glossaryID: glossary!.id).isEmpty)
    }

    func testDeleteGlossaryTreatsIDAsDataNotSQL() {
        let cache = CacheService()
        let service = cache.glossaryService
        let glossary = service.createGlossary(name: "Safe glossary")
        XCTAssertNotNil(glossary)
        _ = service.insertTerm(
            glossaryID: glossary!.id,
            sourceTerm: "守る",
            targetTerm: "protect",
            autoDetected: true
        )

        service.deleteGlossary(id: "' OR 1=1 --")

        XCTAssertTrue(service.listGlossaries().contains { $0.id == glossary!.id })
        XCTAssertEqual(service.listTerms(glossaryID: glossary!.id).count, 1)
    }

    func testInsertDetectedTermsDoesNotDuplicateExistingSourceTerms() {
        let cache = CacheService()
        let service = cache.glossaryService
        let glossary = service.createGlossary(name: "Detected")
        XCTAssertNotNil(glossary)
        _ = service.insertTerm(
            glossaryID: glossary!.id,
            sourceTerm: "花子",
            targetTerm: "Hanako",
            autoDetected: false
        )

        service.insertDetectedTerms([
            GlossaryTerm(id: "detected-1", sourceTerm: "花子", targetTerm: "Hanako alt", autoDetected: true),
            GlossaryTerm(id: "detected-2", sourceTerm: "学校", targetTerm: "school", autoDetected: true)
        ], glossaryID: glossary!.id)

        let terms = service.listTerms(glossaryID: glossary!.id)
        XCTAssertEqual(terms.filter { $0.sourceTerm == "花子" }.count, 1)
        XCTAssertTrue(terms.contains { $0.sourceTerm == "学校" && $0.autoDetected })
    }
}

private func makeTestCGImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8, space: colorSpace, bitmapInfo: 0)!
    return context.makeImage()!
}
