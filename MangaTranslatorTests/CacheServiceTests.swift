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
}

private func makeTestCGImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8, space: colorSpace, bitmapInfo: 0)!
    return context.makeImage()!
}
