import Testing
import CoreGraphics
@testable import MangaTranslator

@Suite("LLMPrompt")
struct LLMPromptTests {

    // MARK: - Helpers

    private func makeBubble(index: Int, text: String = "test") -> BubbleCluster {
        var b = BubbleCluster(
            boundingBox: CGRect(x: 10, y: 10, width: 50, height: 50),
            text: text,
            observations: []
        )
        b.index = index
        return b
    }

    // MARK: - userPrompt uses bubble.index, not enumeration offset

    @Test("userPrompt preserves original bubble.index after filtering")
    func userPromptPreservesBubbleIndex() {
        // Simulate post-filter bubbles: indices [0, 2, 3] (index 1 was punctuation-only)
        let bubbles = [
            makeBubble(index: 0, text: "Hello"),
            makeBubble(index: 2, text: "World"),
            makeBubble(index: 3, text: "!?")
        ]

        let prompt = LLMPrompt.userPrompt(bubbles: bubbles)

        // Each bubble's original index must appear, not 0/1/2
        #expect(prompt.contains("\"index\": 0"))
        #expect(prompt.contains("\"index\": 2"))
        #expect(prompt.contains("\"index\": 3"))
        // Enumeration offset 1 must NOT appear as an index for the second bubble
        #expect(!prompt.contains("\"index\": 1"))
    }

    // MARK: - System prompt does not contain "reorder" instruction

    @Test("systemPrompt does not instruct LLM to reorder bubbles")
    func systemPromptNoReorderInstruction() {
        let prompt = LLMPrompt.systemPrompt(from: .ja, to: .en)

        #expect(!prompt.lowercased().contains("reorder"))
        #expect(!prompt.contains("corrected reading order"))
    }

    @Test("systemPrompt instructs LLM to echo back index unchanged")
    func systemPromptEchoIndexInstruction() {
        let prompt = LLMPrompt.systemPrompt(from: .ja, to: .en)

        #expect(prompt.lowercased().contains("echo"))
    }
}

@Suite("LLMResponseParser")
struct LLMResponseParserTests {

    private func makeBubble(index: Int, text: String = "text") -> BubbleCluster {
        var b = BubbleCluster(
            boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
            text: text,
            observations: []
        )
        b.index = index
        return b
    }

    // MARK: - Dictionary lookup: non-sequential indices map correctly

    @Test("parser maps non-sequential indices to correct bubbles")
    func parserDictionaryLookupNonSequential() throws {
        // Bubbles have indices [0, 2, 3] - index 1 was filtered out
        let bubbles = [
            makeBubble(index: 0, text: "A"),
            makeBubble(index: 2, text: "B"),
            makeBubble(index: 3, text: "C")
        ]

        // LLM echoes back the same indices
        let json = """
        [
          {"index": 0, "translation": "Translated A"},
          {"index": 2, "translation": "Translated B"},
          {"index": 3, "translation": "Translated C"}
        ]
        """

        let (translated, _) = try LLMResponseParser.parse(json, bubbles: bubbles)

        let byIndex = Dictionary(uniqueKeysWithValues: translated.map { ($0.bubble.index, $0) })
        #expect(byIndex[0]?.translatedText == "Translated A")
        #expect(byIndex[0]?.bubble.text == "A")
        #expect(byIndex[2]?.translatedText == "Translated B")
        #expect(byIndex[2]?.bubble.text == "B")
        #expect(byIndex[3]?.translatedText == "Translated C")
        #expect(byIndex[3]?.bubble.text == "C")
    }

    // MARK: - Parser silently drops unknown indices

    @Test("parser silently drops items with unknown index")
    func parserDropsUnknownIndex() throws {
        let bubbles = [
            makeBubble(index: 0, text: "A"),
            makeBubble(index: 1, text: "B")
        ]

        // LLM returns index 99 which was never sent
        let json = """
        [
          {"index": 0, "translation": "Translated A"},
          {"index": 99, "translation": "Should be dropped"}
        ]
        """

        let (translated, _) = try LLMResponseParser.parse(json, bubbles: bubbles)

        #expect(translated.count == 1)
        #expect(translated[0].bubble.text == "A")
    }
}
