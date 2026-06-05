import Testing
import CoreGraphics
import Foundation
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
    func userPromptPreservesBubbleIndex() throws {
        // Simulate post-filter bubbles: indices [0, 2, 3] (index 1 was punctuation-only)
        let bubbles = [
            makeBubble(index: 0, text: "Hello"),
            makeBubble(index: 2, text: "World"),
            makeBubble(index: 3, text: "!?")
        ]

        let prompt = LLMPrompt.userPrompt(bubbles: bubbles)
        let data = try #require(prompt.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let indices = json.compactMap { $0["index"] as? Int }

        // Each bubble's original index must appear, not 0/1/2
        #expect(indices == [0, 2, 3])
        // Enumeration offset 1 must NOT appear as an index for the second bubble
        #expect(!indices.contains(1))
    }

    @Test("userPrompt emits valid JSON when bubble text contains escapes")
    func userPromptEscapesJSONStringContent() throws {
        let bubbles = [
            makeBubble(index: 5, text: "quote \" slash \\ newline\nend")
        ]

        let prompt = LLMPrompt.userPrompt(bubbles: bubbles)
        let data = try #require(prompt.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        #expect(json?.first?["index"] as? Int == 5)
        #expect(json?.first?["text"] as? String == "quote \" slash \\ newline\nend")
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

    @Test("systemPrompt uses expanded language display names")
    func systemPromptUsesExpandedLanguageDisplayNames() {
        let prompt = LLMPrompt.systemPrompt(from: .en, to: .ptBR)

        #expect(prompt.contains("🇺🇸 English"))
        #expect(prompt.contains("🇧🇷 Portuguese (Brazil)"))
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

    @Test("parser accepts fenced JSON and extracts detected terms")
    func parserAcceptsFencedJSONAndDetectedTerms() throws {
        let bubbles = [makeBubble(index: 0, text: "花子")]
        let json = """
        ```json
        [
          {
            "index": 0,
            "translation": "Hanako",
            "detected_terms": [
              {"source": "花子", "target": "Hanako"}
            ]
          }
        ]
        ```
        """

        let (translated, terms) = try LLMResponseParser.parse(json, bubbles: bubbles)

        #expect(translated.first?.translatedText == "Hanako")
        #expect(terms.count == 1)
        #expect(terms.first?.sourceTerm == "花子")
        #expect(terms.first?.targetTerm == "Hanako")
        #expect(terms.first?.autoDetected == true)
    }

    // MARK: - Multi-page parser

    private func makePageInput(pageId: String, bubbleIndices: [Int]) -> BatchPageInput {
        let bubbles = bubbleIndices.map { makeBubble(index: $0, text: "src-\(pageId)-\($0)") }
        return BatchPageInput(pageId: pageId, bubbles: bubbles)
    }

    @Test("parseMultiPage returns BatchPageOutput in requested page-id order")
    func parserMultiPageMapsByPageId() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0]),
            makePageInput(pageId: "2", bubbleIndices: [0]),
            makePageInput(pageId: "3", bubbleIndices: [0])
        ]
        // Response intentionally shuffled
        let json = """
        {
          "pages": [
            {"page_id": "3", "bubbles": [{"index": 0, "translation": "T3"}]},
            {"page_id": "1", "bubbles": [{"index": 0, "translation": "T1"}]},
            {"page_id": "2", "bubbles": [{"index": 0, "translation": "T2"}]}
          ]
        }
        """

        let outputs = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)

        #expect(outputs.map { $0.pageId } == ["1", "2", "3"])
        #expect(outputs[0].bubbles.first?.translatedText == "T1")
        #expect(outputs[1].bubbles.first?.translatedText == "T2")
        #expect(outputs[2].bubbles.first?.translatedText == "T3")
    }

    @Test("parseMultiPage throws MultiPageParseError.missingPage when a requested page id is absent")
    func parserMultiPageRejectsMissingPageId() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0]),
            makePageInput(pageId: "2", bubbleIndices: [0]),
            makePageInput(pageId: "3", bubbleIndices: [0])
        ]
        let json = """
        {
          "pages": [
            {"page_id": "1", "bubbles": [{"index": 0, "translation": "T1"}]},
            {"page_id": "3", "bubbles": [{"index": 0, "translation": "T3"}]}
          ]
        }
        """

        var thrown: Error?
        do {
            _ = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)
        } catch {
            thrown = error
        }

        let multiPageError = try #require(thrown as? LLMResponseParser.MultiPageParseError)
        if case .missingPage(let id) = multiPageError {
            #expect(id == "2")
        } else {
            Issue.record("Expected .missingPage, got \(multiPageError)")
        }
    }

    @Test("parseMultiPage throws MultiPageParseError.duplicatePage when a page id repeats")
    func parserMultiPageRejectsDuplicatePageId() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0]),
            makePageInput(pageId: "2", bubbleIndices: [0])
        ]
        let json = """
        {
          "pages": [
            {"page_id": "1", "bubbles": [{"index": 0, "translation": "T1"}]},
            {"page_id": "1", "bubbles": [{"index": 0, "translation": "T1-dup"}]},
            {"page_id": "2", "bubbles": [{"index": 0, "translation": "T2"}]}
          ]
        }
        """

        var thrown: Error?
        do {
            _ = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)
        } catch {
            thrown = error
        }

        let multiPageError = try #require(thrown as? LLMResponseParser.MultiPageParseError)
        if case .duplicatePage(let id) = multiPageError {
            #expect(id == "1")
        } else {
            Issue.record("Expected .duplicatePage, got \(multiPageError)")
        }
    }

    @Test("parseMultiPage throws MultiPageParseError.missingBubble when a requested bubble index is absent")
    func parserMultiPageRejectsMissingBubble() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0, 1, 2])
        ]
        let json = """
        {
          "pages": [
            {"page_id": "1", "bubbles": [
              {"index": 0, "translation": "T0"},
              {"index": 2, "translation": "T2"}
            ]}
          ]
        }
        """

        var thrown: Error?
        do {
            _ = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)
        } catch {
            thrown = error
        }

        let multiPageError = try #require(thrown as? LLMResponseParser.MultiPageParseError)
        if case .missingBubble(let pageId, let index) = multiPageError {
            #expect(pageId == "1")
            #expect(index == 1)
        } else {
            Issue.record("Expected .missingBubble, got \(multiPageError)")
        }
    }

    @Test("parseMultiPage throws MultiPageParseError.unexpectedBubble when an unrequested bubble index appears")
    func parserMultiPageRejectsUnexpectedBubble() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0, 1])
        ]
        let json = """
        {
          "pages": [
            {"page_id": "1", "bubbles": [
              {"index": 0, "translation": "T0"},
              {"index": 1, "translation": "T1"},
              {"index": 99, "translation": "ghost"}
            ]}
          ]
        }
        """

        var thrown: Error?
        do {
            _ = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)
        } catch {
            thrown = error
        }

        let multiPageError = try #require(thrown as? LLMResponseParser.MultiPageParseError)
        if case .unexpectedBubble(let pageId, let index) = multiPageError {
            #expect(pageId == "1")
            #expect(index == 99)
        } else {
            Issue.record("Expected .unexpectedBubble, got \(multiPageError)")
        }
    }

    @Test("parseMultiPage throws MultiPageParseError.unexpectedBubble when the same bubble index repeats")
    func parserMultiPageRejectsDuplicateBubble() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0, 1])
        ]
        let json = """
        {
          "pages": [
            {"page_id": "1", "bubbles": [
              {"index": 0, "translation": "T0"},
              {"index": 1, "translation": "T1"},
              {"index": 0, "translation": "T0-dup"}
            ]}
          ]
        }
        """

        var thrown: Error?
        do {
            _ = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)
        } catch {
            thrown = error
        }

        let multiPageError = try #require(thrown as? LLMResponseParser.MultiPageParseError)
        if case .unexpectedBubble(let pageId, let index) = multiPageError {
            #expect(pageId == "1")
            #expect(index == 0)
        } else {
            Issue.record("Expected .unexpectedBubble, got \(multiPageError)")
        }
    }

    @Test("parseMultiPage throws MultiPageParseError.unexpectedPage when response contains an unrequested page id")
    func parserMultiPageRejectsExtraPageId() throws {
        let inputs = [
            makePageInput(pageId: "1", bubbleIndices: [0]),
            makePageInput(pageId: "2", bubbleIndices: [0])
        ]
        let json = """
        {
          "pages": [
            {"page_id": "1", "bubbles": [{"index": 0, "translation": "T1"}]},
            {"page_id": "2", "bubbles": [{"index": 0, "translation": "T2"}]},
            {"page_id": "9", "bubbles": [{"index": 0, "translation": "T9"}]}
          ]
        }
        """

        var thrown: Error?
        do {
            _ = try LLMResponseParser.parseMultiPage(json, pageInputs: inputs)
        } catch {
            thrown = error
        }

        let multiPageError = try #require(thrown as? LLMResponseParser.MultiPageParseError)
        if case .unexpectedPage(let id) = multiPageError {
            #expect(id == "9")
        } else {
            Issue.record("Expected .unexpectedPage, got \(multiPageError)")
        }
    }
}

@Suite("LLMPrompt multi-page")
struct LLMPromptMultiPageTests {

    private func makeBubble(index: Int, text: String = "test") -> BubbleCluster {
        var b = BubbleCluster(
            boundingBox: CGRect(x: 10, y: 10, width: 50, height: 50),
            text: text,
            observations: []
        )
        b.index = index
        return b
    }

    private func makePageInput(pageId: String, bubbleCount: Int = 1) -> BatchPageInput {
        let bubbles = (0..<bubbleCount).map { makeBubble(index: $0, text: "p\(pageId)-b\($0)") }
        return BatchPageInput(pageId: pageId, bubbles: bubbles)
    }

    // Find every occurrence of a substring; used to verify exactly-once and ordering invariants.
    private func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var results: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while let r = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            results.append(r)
            searchStart = r.upperBound
        }
        return results
    }

    @Test("multiPageUserPrompt lists pages by page_id in ascending request order")
    func multiPageUserPromptListsPagesInIndexOrder() throws {
        let inputs = [
            makePageInput(pageId: "1"),
            makePageInput(pageId: "2"),
            makePageInput(pageId: "3")
        ]

        let prompt = LLMPrompt.multiPageUserPrompt(pageInputs: inputs)

        // Be tolerant of JSON whitespace variation across Foundation versions
        // by normalising the prompt before comparing.
        let normalised = prompt
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")

        let r1 = try #require(normalised.range(of: "\"page_id\":\"1\""))
        let r2 = try #require(normalised.range(of: "\"page_id\":\"2\""))
        let r3 = try #require(normalised.range(of: "\"page_id\":\"3\""))
        #expect(r1.lowerBound < r2.lowerBound)
        #expect(r2.lowerBound < r3.lowerBound)
        // No stray ids
        #expect(normalised.range(of: "\"page_id\":\"4\"") == nil)
    }

    @Test("multiPageSystemPrompt includes exactly one Recent context block when prior pages exist and instructs multi-page response")
    func multiPageSystemPromptIncludesRecentContextOnceWhenPriorPagesExist() {
        let context = TranslationContext(
            glossaryTerms: [],
            recentPageSummaries: ["page-A-summary", "page-B-summary"]
        )

        let prompt = LLMPrompt.multiPageSystemPrompt(from: .ja, to: .en, context: context)

        let recentBlocks = ranges(of: "## Recent context", in: prompt)
        #expect(recentBlocks.count == 1)
        let a = prompt.range(of: "page-A-summary")
        let b = prompt.range(of: "page-B-summary")
        #expect(a != nil, "Expected 'page-A-summary' in prompt")
        #expect(b != nil, "Expected 'page-B-summary' in prompt")
        if let a, let b {
            #expect(a.lowerBound < b.lowerBound)
        }
        // Response instruction must mention the multi-page object shape, not the per-page array shape.
        #expect(prompt.contains("\"pages\""))
    }

    @Test("multiPageSystemPrompt omits Recent context when prior pages are empty")
    func multiPageSystemPromptOmitsRecentContextWhenPriorPagesEmpty() {
        let prompt = LLMPrompt.multiPageSystemPrompt(
            from: .ja,
            to: .en,
            context: TranslationContext(glossaryTerms: [], recentPageSummaries: [])
        )

        #expect(!prompt.contains("## Recent context"))
    }

    @Test("multiPageUserPrompt has no Recent context block for any internal page")
    func multiPageUserPromptDoesNotInjectRecentContextForBatchInternalPages() {
        let inputs = [
            makePageInput(pageId: "1"),
            makePageInput(pageId: "2"),
            makePageInput(pageId: "3")
        ]

        let prompt = LLMPrompt.multiPageUserPrompt(pageInputs: inputs)

        #expect(!prompt.contains("## Recent context"))
    }
}
