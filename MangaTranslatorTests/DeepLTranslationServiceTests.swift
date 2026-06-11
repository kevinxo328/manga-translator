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
            let data = Data(#"{"translations":[{"text":"ok"}]}"#.utf8)
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

// Terms that are substrings of other terms must not produce nested tags:
// `<x>…<x>短</x>…</x>` survives revert as tag fragments in the final text.
@Suite("GlossarySubstitution XML")
struct GlossarySubstitutionXMLTests {
    private let tower = GlossaryTerm(id: "t1", sourceTerm: "東京タワー", targetTerm: "Tokyo Tower", autoDetected: false)
    private let tokyo = GlossaryTerm(id: "t2", sourceTerm: "東京", targetTerm: "Tokyo", autoDetected: false)

    @Test("term that is a substring of a longer term does not nest tags")
    func substringTermDoesNotNestTags() {
        let wrapped = GlossarySubstitution.applyXML(to: "東京タワーが見える", terms: [tokyo, tower])
        #expect(wrapped == "<x>東京タワー</x>が見える")
    }

    @Test("standalone occurrence of the shorter term is still wrapped")
    func standaloneShorterTermIsWrapped() {
        let wrapped = GlossarySubstitution.applyXML(to: "東京と東京タワー", terms: [tokyo, tower])
        #expect(wrapped == "<x>東京</x>と<x>東京タワー</x>")
    }

    @Test("revert after apply leaves no tag fragments")
    func revertLeavesNoTagFragments() {
        let wrapped = GlossarySubstitution.applyXML(to: "東京タワーと東京", terms: [tokyo, tower])
        let reverted = GlossarySubstitution.revertXML(wrapped, terms: [tokyo, tower])
        #expect(reverted == "Tokyo TowerとTokyo")
    }
}
