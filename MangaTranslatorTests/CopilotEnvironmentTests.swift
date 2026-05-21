import Foundation
import Testing
@testable import MangaTranslator

@Suite("CopilotEnvironment")
struct CopilotEnvironmentTests {

    @Test("notInstalled when binary absent")
    func notInstalledWhenBinaryAbsent() {
        let result = CopilotEnvironment.binaryPath(searchingIn: ["/nonexistent/path"])
        #expect(result == nil)
    }

    @Test("parseModels keeps usable chat models even when hidden from Copilot's picker")
    func parseModelsKeepsUsableChatModelsHiddenFromCopilotPicker() throws {
        let json = """
        {
          "data": [
            {
              "id": "claude-sonnet-4.5",
              "name": "Claude Sonnet 4.5",
              "model_picker_enabled": false,
              "model_picker_category": "versatile",
              "policy": { "state": "enabled" },
              "capabilities": { "type": "chat" },
              "supported_endpoints": ["/chat/completions", "/v1/messages"]
            },
            {
              "id": "blocked-model",
              "name": "Blocked Model",
              "model_picker_enabled": true,
              "policy": { "state": "disabled" },
              "capabilities": { "type": "chat" },
              "supported_endpoints": ["/chat/completions"]
            },
            {
              "id": "text-embedding-3-small",
              "name": "Embedding",
              "model_picker_enabled": true,
              "policy": { "state": "enabled" },
              "capabilities": { "type": "embeddings" },
              "supported_endpoints": ["/embeddings"]
            },
            {
              "id": "gpt-4o",
              "name": "GPT-4o"
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        #expect(models.count == 2)
        #expect(models.map(\.id).sorted() == ["claude-sonnet-4.5", "gpt-4o"])
    }

    @Test("parseModels excludes only picker-disabled models without usable chat signals")
    func parseModelsExcludesPickerDisabledModelsWithoutUsableChatSignals() throws {
        let json = """
        {
          "data": [
            { "id": "true-model",    "name": "True",    "model_picker_enabled": true },
            { "id": "false-model",   "name": "False",   "model_picker_enabled": false },
            { "id": "null-model",    "name": "Null",    "model_picker_enabled": null },
            { "id": "missing-model", "name": "Missing" }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        #expect(models.map(\.id).sorted() == ["missing-model", "null-model", "true-model"])
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

// MARK: - Network tests (serialized due to shared URLProtocol state)

@Suite("CopilotEnvironment fetchModels", .serialized)
final class CopilotEnvironmentFetchModelsTests {

    init() {
        CopilotMockURLProtocol.reset()
    }

    deinit {
        CopilotMockURLProtocol.reset()
    }

    @Test("fetchModels sends vscode-chat integration id and api version header")
    func fetchModelsUsesVSCodeIntegrationHeaders() async throws {
        let enabledJSON = """
        { "data": [ { "id": "m1", "name": "M1", "model_picker_enabled": true } ] }
        """.data(using: .utf8)!
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, enabledJSON, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        let models = try await CopilotEnvironment.fetchModels(token: "tok-abc", session: session)
        #expect(models.map(\.id) == ["m1"])

        let requests = CopilotMockURLProtocol.captured()
        let firstRequest = try #require(requests.first)
        #expect(firstRequest.value(forHTTPHeaderField: "Copilot-Integration-Id") == "vscode-chat")
        #expect(firstRequest.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(firstRequest.value(forHTTPHeaderField: "Authorization") == "Bearer tok-abc")
    }

    @Test("fetchModels falls back when first endpoint returns only disabled models")
    func fetchModelsFallsBackWhenFirstEndpointReturnsOnlyDisabledModels() async throws {
        let disabledJSON = """
        {
          "data": [
            {
              "id": "d1",
              "name": "Disabled1",
              "model_picker_enabled": false,
              "policy": { "state": "disabled" },
              "capabilities": { "type": "chat" },
              "supported_endpoints": ["/chat/completions"]
            },
            {
              "id": "d2",
              "name": "Disabled2",
              "model_picker_enabled": true,
              "policy": { "state": "enabled" },
              "capabilities": { "type": "embeddings" },
              "supported_endpoints": ["/embeddings"]
            }
          ]
        }
        """.data(using: .utf8)!
        let enabledJSON = """
        { "data": [ { "id": "from-fallback", "name": "Fallback", "model_picker_enabled": true } ] }
        """.data(using: .utf8)!

        CopilotMockURLProtocol.setHandler { request in
            let host = request.url?.host ?? ""
            let body = host.contains("individual") ? disabledJSON : enabledJSON
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        let models = try await CopilotEnvironment.fetchModels(token: "tok", session: session)
        #expect(models.map(\.id) == ["from-fallback"])

        let hosts = CopilotMockURLProtocol.captured().compactMap { $0.url?.host }
        #expect(hosts == ["api.individual.githubcopilot.com", "api.githubcopilot.com"])
    }

    @Test("fetchModels falls back on HTTP error")
    func fetchModelsFallsBackOnHTTPError() async throws {
        let enabledJSON = """
        { "data": [ { "id": "from-fallback", "name": "Fallback", "model_picker_enabled": true } ] }
        """.data(using: .utf8)!

        CopilotMockURLProtocol.setHandler { request in
            let host = request.url?.host ?? ""
            let url = request.url!
            if host.contains("individual") {
                let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data(), nil)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, enabledJSON, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        let models = try await CopilotEnvironment.fetchModels(token: "tok", session: session)
        #expect(models.map(\.id) == ["from-fallback"])
    }

    @Test("fetchModels returns empty when all endpoints exhausted")
    func fetchModelsReturnsEmptyWhenAllEndpointsExhausted() async throws {
        let disabledJSON = """
        { "data": [ { "id": "d", "name": "D", "model_picker_enabled": false } ] }
        """.data(using: .utf8)!

        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, disabledJSON, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        let models = try await CopilotEnvironment.fetchModels(token: "tok", session: session)
        #expect(models.isEmpty)
        #expect(CopilotMockURLProtocol.captured().count == 2)
    }
}

// MARK: - URLProtocol helper (shared by serialized fetchModels tests)

final class CopilotMockURLProtocol: URLProtocol {

    typealias Handler = (URLRequest) -> (HTTPURLResponse, Data, Error?)

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _capturedRequests: [URLRequest] = []

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        _handler = handler
        lock.unlock()
    }

    static func captured() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedRequests
    }

    static func reset() {
        lock.lock()
        _handler = nil
        _capturedRequests = []
        lock.unlock()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CopilotMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._capturedRequests.append(request)
        let handler = Self._handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data, error) = handler(request)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
