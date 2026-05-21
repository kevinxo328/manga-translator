import Testing
import Foundation
@testable import MangaTranslator

@Suite("OpenAITranslationService")
struct OpenAITranslationServiceTests {

    // MARK: - Base URL validation (happens before keychain check)

    @Test("translate throws BaseURLValidatorError when base URL has a query string")
    func throwsOnQueryStringBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "https://api.openai.com/v1?inject=1")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }

    @Test("translate throws BaseURLValidatorError when base URL has a fragment")
    func throwsOnFragmentBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "https://api.openai.com/v1#frag")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }

    @Test("translate throws BaseURLValidatorError when base URL uses HTTP with remote host")
    func throwsOnHTTPRemoteBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "http://api.openai.com/v1")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }

    @Test("translate throws BaseURLValidatorError when base URL is empty")
    func throwsOnEmptyBaseURL() async {
        let service = OpenAITranslationService(model: "gpt-5", baseURL: "")
        await #expect(throws: BaseURLValidatorError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .zhHant, context: .empty)
        }
    }
}

// MARK: - Non-2xx provider error tests

@Suite("OpenAITranslationService non-2xx")
struct OpenAITranslationServiceErrorTests {

    private func makeService(session: URLSession) -> OpenAITranslationService {
        OpenAITranslationService(
            model: "gpt-5",
            baseURL: "https://api.openai.com/v1",
            keychainService: .mocked(returning: "sk-test-key"),
            urlSession: session
        )
    }

    private func makeBubble() -> BubbleCluster {
        BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [])
    }

    @Test("non-2xx throws sanitized provider API error with parsed code and message")
    func nonSuccessThrowsSanitizedError() async throws {
        let body = Data(#"""
        {"error":{"message":"Invalid API key sk-secret1234567890abcdef1234567890","type":"invalid_request_error","code":"invalid_api_key"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.translate(bubbles: [makeBubble()], from: .ja, to: .zhHant, context: .empty)
            Issue.record("Expected translate to throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "OpenAI Compatible")
            #expect(sanitized.statusCode == 401)
            #expect(sanitized.code == "invalid_api_key")
            let message = try #require(sanitized.message)
            #expect(!message.contains("sk-secret1234567890abcdef1234567890"))
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("localizedDescription excludes raw sensitive body content")
    func localizedDescriptionExcludesSensitiveContent() async throws {
        let body = Data(#"""
        {"error":{"message":"Token leaked: Bearer ghp_1234567890abcdef1234567890abcdef1234 user a@b.com","code":"unauthorized"}}
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
            #expect(description.contains("OpenAI Compatible"))
            #expect(description.contains("401"))
            #expect(!description.contains("ghp_1234567890abcdef1234567890abcdef1234"))
            #expect(!description.contains("a@b.com"))
        }
    }
}
