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
