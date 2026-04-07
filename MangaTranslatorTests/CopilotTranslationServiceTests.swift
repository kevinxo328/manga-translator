import Testing
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
