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
