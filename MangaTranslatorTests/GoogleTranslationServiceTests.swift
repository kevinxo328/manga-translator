import Testing
import Foundation
@testable import MangaTranslator

@Suite("GoogleTranslationService non-2xx")
struct GoogleTranslationServiceTests {

    private func makeService(session: URLSession) -> GoogleTranslationService {
        GoogleTranslationService(
            keychainService: .mocked(returning: "AIza-google-test-key-1234567890"),
            urlSession: session
        )
    }

    private func makeBubble() -> BubbleCluster {
        BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [])
    }

    @Test("Google sends API key in header instead of URL query")
    func googleUsesAPIKeyHeader() async throws {
        let expectedAPIKey = "AIza-google-test-key-1234567890"
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: Data(), request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"data":{"translations":[{"translatedText":"ok"}]}}"#.utf8)
            return (response, data)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let output = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .en, context: .empty)

        let request = try #require(counter.capturedRequests.first)
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.queryItems?.contains { $0.name == "key" } != true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == expectedAPIKey)
        #expect(output.bubbles.first?.translatedText == "ok")
    }

    @Test("Google request body uses provider language codes for every target language")
    func googleRequestBodyLanguageCodes() async throws {
        let expectedCodes: [(Language, String)] = [
            (.en, "en"),
            (.fr, "fr"),
            (.de, "de"),
            (.id, "id"),
            (.ja, "ja"),
            (.ko, "ko"),
            (.ptBR, "pt-BR"),
            (.zhHans, "zh-CN"),
            (.es, "es"),
            (.zhHant, "zh-TW"),
            (.vi, "vi")
        ]

        for (language, expectedCode) in expectedCodes {
            let session = ProviderHTTPMockURLProtocol.makeSession { request in
                let body = request.jsonMockBody()
                #expect(body["source"] as? String == "ja")
                #expect(body["target"] as? String == expectedCode)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = Data(#"{"data":{"translations":[{"translatedText":"ok"}]}}"#.utf8)
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
    // Google must not renumber them or downstream index-based pairing breaks.
    @Test("Google preserves original bubble indices instead of renumbering")
    func googlePreservesBubbleIndices() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"data":{"translations":[{"translatedText":"hello"},{"translatedText":"goodbye"}]}}"#.utf8)
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

    // Google v2's `q` field accepts up to 128 strings per request, so a page
    // of N bubbles must cost 1 round-trip, not N. The response `translations`
    // list corresponds positionally to the `q` entries.
    @Test("Google sends all bubbles of a page in a single request, in order")
    func googleBatchesPageIntoSingleRequest() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"data":{"translations":[{"translatedText":"one"},{"translatedText":"two"},{"translatedText":"three"}]}}"#.utf8
            )
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
        #expect(body?["q"] as? [String] == ["壱", "弐", "参"])
        #expect(output.bubbles.map(\.translatedText) == ["one", "two", "three"])
    }

    @Test("Google throws invalidResponse when translation count mismatches request")
    func googleThrowsOnTranslationCountMismatch() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"data":{"translations":[{"translatedText":"only-one"}]}}"#.utf8)
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

    // Google caps `q` at 128 strings per request; 129 bubbles must split
    // into two requests of 128 + 1 instead of one oversized (rejected) call.
    @Test("Google chunks pages with more than 128 bubbles into multiple requests")
    func googleChunksBeyondLimit() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let body = request.jsonMockBody()
            let texts = body["q"] as? [String] ?? []
            let translations = texts.map { #"{"translatedText":"t-\#($0)"}"# }.joined(separator: ",")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":{"translations":[\#(translations)]}}"#.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let bubbles = (0..<129).map {
            BubbleCluster(boundingBox: .zero, text: "b\($0)", observations: [], index: $0)
        }
        let service = makeService(session: session)
        let output = try await service.translate(bubbles: bubbles, from: .ja, to: .en, context: .empty)

        #expect(counter.count == 2)
        let firstBody = try JSONSerialization.jsonObject(with: #require(counter.capturedBodies.first)) as? [String: Any]
        #expect((firstBody?["q"] as? [String])?.count == 128)
        #expect(output.bubbles.map(\.translatedText) == (0..<129).map { "t-b\($0)" })
        #expect(output.bubbles.map(\.index) == Array(0..<129))
    }

    @Test("Google PERMISSION_DENIED yields sanitized error with status as code")
    func googlePermissionDenied() async throws {
        let body = Data(#"""
        {"error":{"code":403,"message":"The request is missing a valid API key.","errors":[{"reason":"FORBIDDEN"}],"status":"PERMISSION_DENIED"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "Google Translate")
            #expect(sanitized.statusCode == 403)
            #expect(sanitized.code == "PERMISSION_DENIED")
            #expect(sanitized.message == "The request is missing a valid API key.")
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("Google falls back to errors[].reason when status missing")
    func googleFallsBackToReason() async throws {
        let body = Data(#"{"error":{"code":400,"message":"Invalid value","errors":[{"reason":"badRequest"}]}}"#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.code == "badRequest")
            #expect(sanitized.message == "Invalid value")
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("Google localizedDescription excludes sensitive content from message")
    func googleExcludesSensitive() async throws {
        let body = Data(#"""
        {"error":{"code":401,"message":"API key AIzaSyA-secret-9876543210abcdefghijkl invalid; contact a@b.com","status":"UNAUTHENTICATED"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            let description = try #require(error.errorDescription)
            #expect(description.contains("Google Translate"))
            #expect(description.contains("401"))
            #expect(!description.contains("AIzaSyA-secret-9876543210abcdefghijkl"))
            #expect(!description.contains("a@b.com"))
        }
    }
}

// Terms that are substrings of other terms must not produce nested spans:
// nested `translate="no"` spans survive revert as tag fragments.
@Suite("GlossarySubstitution HTML")
struct GlossarySubstitutionHTMLTests {
    private let tower = GlossaryTerm(id: "t1", sourceTerm: "東京タワー", targetTerm: "Tokyo Tower", autoDetected: false)
    private let tokyo = GlossaryTerm(id: "t2", sourceTerm: "東京", targetTerm: "Tokyo", autoDetected: false)

    @Test("term that is a substring of a longer term does not nest spans")
    func substringTermDoesNotNestSpans() {
        let wrapped = GlossarySubstitution.applyHTML(to: "東京タワーが見える", terms: [tokyo, tower])
        #expect(wrapped == "<span translate=\"no\" data-mt-glossary=\"t1\">東京タワー</span>が見える")
    }

    @Test("standalone occurrence of the shorter term is still wrapped")
    func standaloneShorterTermIsWrapped() {
        let wrapped = GlossarySubstitution.applyHTML(to: "東京と東京タワー", terms: [tokyo, tower])
        #expect(wrapped == "<span translate=\"no\" data-mt-glossary=\"t2\">東京</span>と<span translate=\"no\" data-mt-glossary=\"t1\">東京タワー</span>")
    }

    @Test("revert after apply leaves no span fragments")
    func revertLeavesNoSpanFragments() {
        let wrapped = GlossarySubstitution.applyHTML(to: "東京タワーと東京", terms: [tokyo, tower])
        let reverted = GlossarySubstitution.revertHTML(wrapped, terms: [tokyo, tower])
        #expect(reverted == "Tokyo TowerとTokyo")
    }

    @Test("revert uses marker id when Google rewrites span attributes")
    func revertUsesMarkerIDWhenAttributesChange() {
        let translated = "<SPAN data-mt-glossary='t1' translate = 'no'>rewritten</SPAN>"
        let reverted = GlossarySubstitution.revertHTML(translated, terms: [tokyo, tower])
        #expect(reverted == "Tokyo Tower")
    }

    @Test("revert falls back to source text for no-translate spans without ids")
    func revertFallsBackToSourceTextWithoutID() {
        let translated = "<span class=\"notranslate\">東京</span>"
        let reverted = GlossarySubstitution.revertHTML(translated, terms: [tokyo, tower])
        #expect(reverted == "Tokyo")
    }

    @Test("revert strips unmatched glossary spans")
    func revertStripsUnmatchedSpans() {
        let translated = "Hello <span translate=\"no\">謎</span>"
        let reverted = GlossarySubstitution.revertHTML(translated, terms: [tokyo, tower])
        #expect(reverted == "Hello 謎")
    }
}
