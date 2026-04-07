import Testing
@testable import MangaTranslator

@Suite("CopilotEnvironment")
struct CopilotEnvironmentTests {

    @Test("notInstalled when binary absent")
    func notInstalledWhenBinaryAbsent() {
        let result = CopilotEnvironment.binaryPath(searchingIn: ["/nonexistent/path"])
        #expect(result == nil)
    }

    @Test("fetchModels filters embedding models")
    func fetchModelsFiltersEmbeddingModels() {
        let all = ["gpt-5-mini", "text-embedding-3-small", "claude-sonnet-4.6", "text-embedding-ada-002"]
        let filtered = CopilotEnvironment.filterChatModels(all)
        #expect(filtered == ["gpt-5-mini", "claude-sonnet-4.6"])
    }
}
