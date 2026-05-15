import Testing
import CoreGraphics
@testable import MangaTranslator

// MARK: - Test Double

final class FakeClipboard: ClipboardWriting {
    var lastWritten: String?
    var shouldSucceed: Bool = true

    func write(_ string: String) -> Bool {
        lastWritten = string
        return shouldSucceed
    }
}

// MARK: - Helpers

private func makeBubble(text: String = "OCR text", translated: String = "Translated text") -> TranslatedBubble {
    let cluster = BubbleCluster(
        boundingBox: CGRect(x: 0, y: 0, width: 100, height: 50),
        text: text,
        observations: []
    )
    return TranslatedBubble(bubble: cluster, translatedText: translated, index: 0)
}

// MARK: - Tests

@Suite("TranslationCard clipboard actions")
struct TranslationCardClipboardTests {

    @Test("Copy Translation writes translatedText to clipboard")
    func copyTranslationWritesTranslatedText() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(text: "原文", translated: "Translated")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyTranslation()

        #expect(clipboard.lastWritten == "Translated")
    }

    @Test("Copy Original Text writes full bubble text")
    func copyOriginalTextWritesFullBubbleText() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(text: "Full original OCR text without truncation", translated: "Translated")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyOriginalText()

        #expect(clipboard.lastWritten == "Full original OCR text without truncation")
    }

    @Test("Copy Both writes correct format")
    func copyBothWritesFormattedString() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(text: "原文", translated: "Translated")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyBoth()

        #expect(clipboard.lastWritten == "Original: 原文\nTranslation: Translated")
    }

    @Test("Clipboard returning false does not crash")
    func clipboardFailureDoesNotCrash() {
        let clipboard = FakeClipboard()
        clipboard.shouldSucceed = false
        let bubble = makeBubble()
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyTranslation()

        #expect(clipboard.lastWritten == "Translated text")
    }

    @Test("Empty translatedText writes empty string without error")
    func emptyTranslatedTextWritesEmptyString() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(translated: "")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyTranslation()

        #expect(clipboard.lastWritten == "")
    }
}
