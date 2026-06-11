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
            let data = Data(#"{"data":{"translations":[{"translatedText":"ok"}]}}"#.utf8)
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
        #expect(wrapped == "<span translate=\"no\">東京タワー</span>が見える")
    }

    @Test("standalone occurrence of the shorter term is still wrapped")
    func standaloneShorterTermIsWrapped() {
        let wrapped = GlossarySubstitution.applyHTML(to: "東京と東京タワー", terms: [tokyo, tower])
        #expect(wrapped == "<span translate=\"no\">東京</span>と<span translate=\"no\">東京タワー</span>")
    }

    @Test("revert after apply leaves no span fragments")
    func revertLeavesNoSpanFragments() {
        let wrapped = GlossarySubstitution.applyHTML(to: "東京タワーと東京", terms: [tokyo, tower])
        let reverted = GlossarySubstitution.revertHTML(wrapped, terms: [tokyo, tower])
        #expect(reverted == "Tokyo TowerとTokyo")
    }
}
