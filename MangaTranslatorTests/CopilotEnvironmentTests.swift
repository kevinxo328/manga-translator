import Testing
@testable import MangaTranslator

@Suite("CopilotEnvironment")
struct CopilotEnvironmentTests {

    @Test("notInstalled when binary absent")
    func notInstalledWhenBinaryAbsent() {
        let result = CopilotEnvironment.binaryPath(searchingIn: ["/nonexistent/path"])
        #expect(result == nil)
    }

    @Test("parseModels excludes only model_picker_enabled=false models")
    func parseModelsFiltersPickerEnabled() throws {
        let json = """
        {
          "data": [
            {
              "id": "claude-sonnet-4.5",
              "name": "Claude Sonnet 4.5",
              "model_picker_enabled": true,
              "model_picker_category": "versatile"
            },
            {
              "id": "gpt-3.5-turbo",
              "name": "GPT 3.5 Turbo",
              "model_picker_enabled": false
            },
            {
              "id": "claude-opus-4.5",
              "name": "Claude Opus 4.5",
              "model_picker_enabled": true,
              "model_picker_category": "powerful"
            },
            {
              "id": "gpt-4o",
              "name": "GPT-4o"
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        #expect(models.count == 3)
        #expect(models.map(\.id).sorted() == ["claude-opus-4.5", "claude-sonnet-4.5", "gpt-4o"])
    }

    @Test("parseModels sorts by name")
    func parseModelsSortsByName() throws {
        let json = """
        {
          "data": [
            { "id": "z", "name": "Z Model", "model_picker_enabled": true },
            { "id": "a", "name": "A Model", "model_picker_enabled": true }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        #expect(models.map(\.name) == ["A Model", "Z Model"])
    }

    @Test("CopilotModel displayLabel uses category")
    func copilotModelDisplayLabel() {
        #expect(CopilotModel(id: "a", name: "Claude Sonnet 4.5", category: "versatile").displayLabel == "Claude Sonnet 4.5 (Standard)")
        #expect(CopilotModel(id: "b", name: "Claude Opus 4.5", category: "powerful").displayLabel == "Claude Opus 4.5 (Premium)")
        #expect(CopilotModel(id: "c", name: "GPT-5 mini", category: "lightweight").displayLabel == "GPT-5 mini (Lite)")
        #expect(CopilotModel(id: "d", name: "Unknown", category: nil).displayLabel == "Unknown")
    }
}
