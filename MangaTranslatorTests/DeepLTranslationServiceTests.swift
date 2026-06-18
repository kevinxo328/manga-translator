import Testing
import Foundation
@testable import MangaTranslator

@Suite("DeepLTranslationService non-2xx")
struct DeepLTranslationServiceTests {

    private func makeService(session: URLSession) -> DeepLTranslationService {
        DeepLTranslationService(
            keychainService: .mocked(returning: "deepl-key:fx"),
            urlSession: session
        )
    }

    private func makeBubble() -> BubbleCluster {
        BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [])
    }

    @Test("DeepL request body uses provider language codes for every target language")
    func deepLRequestBodyLanguageCodes() async throws {
        let expectedCodes: [(Language, String)] = [
            (.en, "EN"),
            (.fr, "FR"),
            (.de, "DE"),
            (.id, "ID"),
            (.ja, "JA"),
            (.ko, "KO"),
            (.ptBR, "PT-BR"),
            (.zhHans, "ZH-HANS"),
            (.es, "ES"),
            (.zhHant, "ZH-HANT"),
            (.vi, "VI")
        ]

        for (language, expectedCode) in expectedCodes {
            let session = ProviderHTTPMockURLProtocol.makeSession { request in
                let body = request.jsonMockBody()
                #expect(body["source_lang"] as? String == "JA")
                #expect(body["target_lang"] as? String == expectedCode)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = Data(#"{"translations":[{"text":"ok"}]}"#.utf8)
                return (response, data)
            }
            defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

            let service = makeService(session: session)
            let output = try await service.translate(bubbles: [makeBubble()], from: .ja, to: language, context: .empty)
            #expect(output.bubbles.first?.translatedText == "ok")
        }
    }

    // `preparePage` filters meaningless bubbles, so `bubble.index` can be
    // non-contiguous (0, 2, …). The LLM path preserves those indices;
    // DeepL must not renumber them or downstream index-based pairing breaks.
    @Test("DeepL preserves original bubble indices instead of renumbering")
    func deepLPreservesBubbleIndices() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"translations":[{"text":"hello"},{"text":"goodbye"}]}"#.utf8)
            return (response, data)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let bubbles = [
            BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [], index: 0),
            BubbleCluster(boundingBox: .zero, text: "さようなら", observations: [], index: 2)
        ]
        let service = makeService(session: session)
        let output = try await service.translate(bubbles: bubbles, from: .ja, to: .zhHant, context: .empty)

        #expect(output.bubbles.map(\.index) == [0, 2])
    }

    // DeepL's `text` field accepts up to 50 texts per request, so a page of
    // N bubbles must cost 1 round-trip, not N. Response order is guaranteed
    // by DeepL to match request order, so pairing back is positional.
    @Test("DeepL sends all bubbles of a page in a single request, in order")
    func deepLBatchesPageIntoSingleRequest() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"translations":[{"text":"one"},{"text":"two"},{"text":"three"}]}"#.utf8)
            return (response, data)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let bubbles = [
            BubbleCluster(boundingBox: .zero, text: "壱", observations: [], index: 0),
            BubbleCluster(boundingBox: .zero, text: "弐", observations: [], index: 1),
            BubbleCluster(boundingBox: .zero, text: "参", observations: [], index: 2)
        ]
        let service = makeService(session: session)
        let output = try await service.translate(bubbles: bubbles, from: .ja, to: .en, context: .empty)

        #expect(counter.count == 1)
        let body = try JSONSerialization.jsonObject(with: #require(counter.capturedBodies.first)) as? [String: Any]
        #expect(body?["text"] as? [String] == ["壱", "弐", "参"])
        #expect(output.bubbles.map(\.translatedText) == ["one", "two", "three"])
    }

    @Test("DeepL throws invalidResponse when translation count mismatches request")
    func deepLThrowsOnTranslationCountMismatch() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"translations":[{"text":"only-one"}]}"#.utf8)
            return (response, data)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let bubbles = [
            BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [], index: 0),
            BubbleCluster(boundingBox: .zero, text: "さようなら", observations: [], index: 1)
        ]
        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: bubbles, from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch TranslationError.invalidResponse {
            // expected
        } catch {
            Issue.record("Expected TranslationError.invalidResponse, got \(error)")
        }
    }

    // DeepL caps `text` at 50 entries per request; 51 bubbles must split
    // into two requests of 50 + 1 instead of one oversized (rejected) call.
    @Test("DeepL chunks pages with more than 50 bubbles into multiple requests")
    func deepLChunksBeyondFiftyTexts() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let body = request.jsonMockBody()
            let texts = body["text"] as? [String] ?? []
            let translations = texts.map { #"{"text":"t-\#($0)"}"# }.joined(separator: ",")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"translations":[\#(translations)]}"#.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let bubbles = (0..<51).map {
            BubbleCluster(boundingBox: .zero, text: "b\($0)", observations: [], index: $0)
        }
        let service = makeService(session: session)
        let output = try await service.translate(bubbles: bubbles, from: .ja, to: .en, context: .empty)

        #expect(counter.count == 2)
        let firstBody = try JSONSerialization.jsonObject(with: #require(counter.capturedBodies.first)) as? [String: Any]
        #expect((firstBody?["text"] as? [String])?.count == 50)
        #expect(output.bubbles.map(\.translatedText) == (0..<51).map { "t-b\($0)" })
        #expect(output.bubbles.map(\.index) == Array(0..<51))
    }

    @Test("DeepL 456 with top-level message yields sanitized error")
    func deepLQuotaError() async throws {
        let body = Data(#"{"message":"Quota for this billing period has been exceeded"}"#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 456, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "DeepL")
            #expect(sanitized.statusCode == 456)
            #expect(sanitized.message == "Quota for this billing period has been exceeded")
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("DeepL localizedDescription redacts credentials and emails from body")
    func deepLRedactsSensitiveContent() async throws {
        let body = Data(#"{"message":"Authorization: DeepL-Auth-Key deepl-leaked-key-12345abcdef67890 for user a@b.com"}"#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            let description = try #require(error.errorDescription)
            #expect(description.contains("DeepL"))
            #expect(description.contains("403"))
            #expect(!description.contains("deepl-leaked-key-12345abcdef67890"))
            #expect(!description.contains("a@b.com"))
        }
    }
}

// The LLM prompt must not carry the whole accumulated glossary — only terms
// whose source actually occurs in the texts being translated. Japanese has no
// word boundaries, so substring containment is the relevance criterion.
@Suite("GlossarySubstitution relevance filter")
struct GlossaryRelevanceFilterTests {
    private let taro = GlossaryTerm(id: "t1", sourceTerm: "太郎", targetTerm: "Taro", autoDetected: false)
    private let hanako = GlossaryTerm(id: "t2", sourceTerm: "花子", targetTerm: "Hanako", autoDetected: true)
    private let tower = GlossaryTerm(id: "t3", sourceTerm: "東京タワー", targetTerm: "Tokyo Tower", autoDetected: true)

    @Test("a term is kept when its source occurs in any of the texts")
    func keepsTermOccurringInAnyText() {
        let kept = GlossarySubstitution.relevantTerms(
            [taro, hanako, tower],
            in: ["太郎です", "東京タワーが見える"]
        )
        #expect(kept.map(\.sourceTerm) == ["太郎", "東京タワー"])
    }

    @Test("terms absent from every text are dropped")
    func dropsTermsAbsentFromAllTexts() {
        let kept = GlossarySubstitution.relevantTerms([taro, hanako], in: ["こんにちは"])
        #expect(kept.isEmpty)
    }

    // Prompt lines follow glossary order; filtering must not reorder terms.
    @Test("filtering preserves the original term order")
    func preservesTermOrder() {
        let kept = GlossarySubstitution.relevantTerms(
            [tower, hanako, taro],
            in: ["花子と太郎と東京タワー"]
        )
        #expect(kept.map(\.sourceTerm) == ["東京タワー", "花子", "太郎"])
    }
}

// Terms that are substrings of other terms must not produce nested tags:
// `<x>…<x>短</x>…</x>` survives revert as tag fragments in the final text.
@Suite("GlossarySubstitution XML")
struct GlossarySubstitutionXMLTests {
    private let tower = GlossaryTerm(id: "t1", sourceTerm: "東京タワー", targetTerm: "Tokyo Tower", autoDetected: false)
    private let tokyo = GlossaryTerm(id: "t2", sourceTerm: "東京", targetTerm: "Tokyo", autoDetected: false)

    @Test("term that is a substring of a longer term does not nest tags")
    func substringTermDoesNotNestTags() {
        let wrapped = GlossarySubstitution.applyXML(to: "東京タワーが見える", terms: [tokyo, tower])
        #expect(wrapped == "<x id=\"t1\">東京タワー</x>が見える")
    }

    @Test("standalone occurrence of the shorter term is still wrapped")
    func standaloneShorterTermIsWrapped() {
        let wrapped = GlossarySubstitution.applyXML(to: "東京と東京タワー", terms: [tokyo, tower])
        #expect(wrapped == "<x id=\"t2\">東京</x>と<x id=\"t1\">東京タワー</x>")
    }

    @Test("revert after apply leaves no tag fragments")
    func revertLeavesNoTagFragments() {
        let wrapped = GlossarySubstitution.applyXML(to: "東京タワーと東京", terms: [tokyo, tower])
        let reverted = GlossarySubstitution.revertXML(wrapped, terms: [tokyo, tower])
        #expect(reverted == "Tokyo TowerとTokyo")
    }

    @Test("revert uses marker id when DeepL preserves x attributes")
    func revertUsesMarkerID() {
        let translated = "<x id='t1'>rewritten</x>"
        let reverted = GlossarySubstitution.revertXML(translated, terms: [tokyo, tower])
        #expect(reverted == "Tokyo Tower")
    }

    @Test("revert falls back to source text for x tags without ids")
    func revertFallsBackToSourceTextWithoutID() {
        let translated = "<x>東京</x>"
        let reverted = GlossarySubstitution.revertXML(translated, terms: [tokyo, tower])
        #expect(reverted == "Tokyo")
    }

    @Test("revert strips unmatched x tags")
    func revertStripsUnmatchedTags() {
        let translated = "Hello <x>謎</x>"
        let reverted = GlossarySubstitution.revertXML(translated, terms: [tokyo, tower])
        #expect(reverted == "Hello 謎")
    }
}
