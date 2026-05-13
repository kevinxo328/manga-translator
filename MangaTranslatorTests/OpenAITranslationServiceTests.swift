import Testing
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
