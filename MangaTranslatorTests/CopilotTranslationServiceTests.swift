import Testing
import Foundation
@testable import MangaTranslator

@Suite("CopilotTranslationService")
struct CopilotTranslationServiceTests {

    @Test("engine is githubCopilot")
    func engineIsGithubCopilot() {
        let service = CopilotTranslationService(model: "gpt-5-mini")
        #expect(service.engine == .githubCopilot)
    }

    @Test("translate throws missingAPIKey when Copilot CLI absent")
    func throwsMissingAPIKeyWhenUnavailable() async throws {
        guard case .notInstalled = CopilotEnvironment.check() else {
            return // copilot is installed, skip this assertion path
        }
        let service = CopilotTranslationService(model: "gpt-5-mini")
        await #expect(throws: TranslationError.self) {
            _ = try await service.translate(
                bubbles: [],
                from: .ja, to: .zhHant,
                context: .empty
            )
        }
    }
}

// MARK: - Non-2xx provider error tests

@Suite("CopilotTranslationService non-2xx")
struct CopilotTranslationServiceErrorTests {

    private func makeService(session: URLSession) -> CopilotTranslationService {
        CopilotTranslationService(model: "gpt-5-mini", urlSession: session)
    }

    @Test("OpenAI-compatible body yields sanitized error")
    func openAICompatibleBody() async throws {
        let body = Data(#"""
        {"error":{"message":"Model not found gpt-5-experimental","type":"invalid_request_error","code":"model_not_found"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.callAPI(systemPrompt: "sys", userPrompt: "user", token: "copilot-token-test")
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "GitHub Copilot")
            #expect(sanitized.statusCode == 404)
            #expect(sanitized.code == "model_not_found")
            #expect(sanitized.message == "Model not found gpt-5-experimental")
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("generic fallback body yields sanitized error without raw payload")
    func genericFallbackBody() async throws {
        let body = Data("<html>Service Unavailable, retry after 30s</html>".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.callAPI(systemPrompt: "sys", userPrompt: "user", token: "copilot-token-test")
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "GitHub Copilot")
            #expect(sanitized.statusCode == 503)
            if let message = sanitized.message {
                #expect(message.count <= APIErrorSanitizer.maxMessageLength)
            }
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("localizedDescription excludes raw bearer tokens and emails")
    func excludesSensitiveContent() async throws {
        let body = Data(#"""
        {"error":{"message":"Authorization: Bearer ghu_secret1234567890abcdef1234567890 user a@b.com","code":"unauthorized"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.callAPI(systemPrompt: "sys", userPrompt: "user", token: "copilot-token-test")
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            let description = try #require(error.errorDescription)
            #expect(description.contains("GitHub Copilot"))
            #expect(description.contains("401"))
            #expect(!description.contains("ghu_secret1234567890abcdef1234567890"))
            #expect(!description.contains("a@b.com"))
        }
    }
}
