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

    @Test("parseModels retains model transport and picker metadata")
    func parseModelsRetainsTransportAndPickerMetadata() throws {
        let json = """
        {
          "data": [
            {
              "id": "gpt-5-mini",
              "name": "GPT-5 mini",
              "model_picker_enabled": true,
              "supported_endpoints": ["/chat/completions", "/responses"],
              "capabilities": { "type": "chat" }
            },
            {
              "id": "metadata-optional",
              "name": "Metadata Optional"
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        let complete = try #require(models.first { $0.id == "gpt-5-mini" })
        #expect(complete.pickerEnabled == true)
        #expect(complete.supportedEndpoints == ["/chat/completions", "/responses"])
        #expect(complete.capabilityType == "chat")

        let optional = try #require(models.first { $0.id == "metadata-optional" })
        #expect(optional.pickerEnabled == nil)
        #expect(optional.supportedEndpoints.isEmpty)
        #expect(optional.capabilityType == nil)
    }

    @Test("CopilotModel classifies exact chat completions support")
    func copilotModelClassifiesExactChatCompletionsSupport() {
        let compatible = CopilotModel(
            id: "compatible",
            name: "Compatible",
            category: nil,
            supportedEndpoints: ["/chat/completions"]
        )
        let responsesOnly = CopilotModel(
            id: "responses-only",
            name: "Responses Only",
            category: nil,
            supportedEndpoints: ["/responses"]
        )
        let missingMetadata = CopilotModel(
            id: "missing-metadata",
            name: "Missing Metadata",
            category: nil
        )

        #expect(compatible.isChatCompletionsCompatible)
        #expect(!responsesOnly.isChatCompletionsCompatible)
        #expect(!missingMetadata.isChatCompletionsCompatible)
    }

    @Test("catalog separates Auto hints from selectable models")
    func catalogSeparatesAutoHintsFromSelectableModels() throws {
        let json = """
        {
          "data": [
            {
              "id": "disabled-auto",
              "name": "Disabled Auto",
              "model_picker_enabled": false,
              "supported_endpoints": ["/chat/completions"]
            },
            {
              "id": "z-selectable",
              "name": "Zeta",
              "model_picker_enabled": true,
              "supported_endpoints": ["/chat/completions"]
            },
            {
              "id": "responses-only",
              "name": "Responses Only",
              "model_picker_enabled": true,
              "supported_endpoints": ["/responses"]
            },
            {
              "id": "a-selectable",
              "name": "Alpha",
              "model_picker_enabled": true,
              "supported_endpoints": ["/chat/completions"]
            }
          ]
        }
        """.data(using: .utf8)!

        let catalog = CopilotModelCatalog(models: try CopilotEnvironment.parseModels(json))

        #expect(catalog.autoHintModelIDs == ["disabled-auto", "z-selectable", "a-selectable"])
        #expect(catalog.selectableModels.map(\.id) == ["a-selectable", "z-selectable"])
    }

    @Test("model load state distinguishes Auto-only and selectable catalogs")
    func modelLoadStateDistinguishesAutoOnlyAndSelectableCatalogs() {
        let autoOnlyCatalog = CopilotModelCatalog(models: [
            CopilotModel(
                id: "auto-only",
                name: "Auto Only",
                category: nil,
                pickerEnabled: false,
                supportedEndpoints: ["/chat/completions"]
            )
        ])
        #expect(CopilotModelLoadState.loaded(from: autoOnlyCatalog) == .autoOnly)

        let selectableCatalog = CopilotModelCatalog(models: [
            CopilotModel(
                id: "selectable",
                name: "Selectable",
                category: nil,
                pickerEnabled: true,
                supportedEndpoints: ["/chat/completions"]
            )
        ])
        guard case .selectable(let models) = CopilotModelLoadState.loaded(from: selectableCatalog) else {
            Issue.record("Expected selectable model state")
            return
        }
        #expect(models.map(\.id) == ["auto", "selectable"])
    }

    @Test("model load state distinguishes no compatible models from fetch failure")
    func modelLoadStateDistinguishesNoCompatibleModelsFromFetchFailure() {
        let incompatibleCatalog = CopilotModelCatalog(models: [
            CopilotModel(
                id: "responses-only",
                name: "Responses Only",
                category: nil,
                supportedEndpoints: ["/responses"]
            )
        ])

        #expect(CopilotModelLoadState.loaded(from: incompatibleCatalog) == .noCompatibleModels)
        #expect(
            CopilotModelLoadState.failed(from: URLError(.timedOut))
                == .failed("Couldn’t load Copilot models.")
        )
    }

    @Test("Copilot engine visibility distinguishes capability from catalog failure")
    func copilotEngineVisibilityDistinguishesCapabilityFromCatalogFailure() {
        #expect(!CopilotAvailability.notInstalled.allowsEngineSelection(modelState: .idle))
        #expect(!CopilotAvailability.notLoggedIn.allowsEngineSelection(modelState: .idle))
        #expect(!CopilotAvailability.available(token: "tok").allowsEngineSelection(modelState: .noCompatibleModels))
        #expect(CopilotAvailability.available(token: "tok").allowsEngineSelection(modelState: .failed("Couldn’t load Copilot models.")))
        #expect(CopilotModelLoadState.failed("Couldn’t load Copilot models.").normalizedCopilotModel("saved") == "saved")
    }

    @Test("parseModels keeps all non-embedding models")
    func parseModelsKeepsAllNonEmbeddingModels() throws {
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
              "id": "disabled-model",
              "name": "Disabled Model",
              "model_picker_enabled": false
            },
            {
              "id": "text-embedding-3-small",
              "name": "Embedding",
              "model_picker_enabled": true
            },
            {
              "id": "gpt-4o",
              "name": "GPT-4o"
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        #expect(models.map(\.id) == ["claude-sonnet-4.5", "disabled-model", "gpt-4o"])
    }

    @Test("parseModels retains picker-disabled models")
    func parseModelsRetainsPickerDisabledModels() throws {
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
        #expect(models.map(\.id) == ["true-model", "false-model", "null-model", "missing-model"])
        #expect(models.first { $0.id == "false-model" }?.pickerEnabled == false)
    }

    @Test("parseModels preserves server order")
    func parseModelsPreservesServerOrder() throws {
        let json = """
        {
          "data": [
            { "id": "z", "name": "Z Model", "model_picker_enabled": true },
            { "id": "a", "name": "A Model", "model_picker_enabled": true }
          ]
        }
        """.data(using: .utf8)!

        let models = try CopilotEnvironment.parseModels(json)
        #expect(models.map(\.name) == ["Z Model", "A Model"])
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

enum CatalogFallbackFailure: CaseIterable, Sendable {
    case transport
    case notFound
    case serverError
    case malformedJSON
    case noNonEmbeddingModels
}

enum TerminalCatalogStatus: Int, CaseIterable, Sendable {
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case rateLimited = 429
}

final class CopilotTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

@Suite("CopilotEnvironment fetchModels", .serialized)
final class CopilotEnvironmentFetchModelsTests {

    init() {
        CopilotMockURLProtocol.reset()
    }

    deinit {
        CopilotMockURLProtocol.reset()
    }

    @Test("fetchModels sends Copilot headers and records successful host")
    func fetchModelsUsesCopilotHeadersAndRecordsSuccessfulHost() async throws {
        let enabledJSON = """
        { "data": [ { "id": "m1", "name": "M1", "model_picker_enabled": true } ] }
        """.data(using: .utf8)!
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, enabledJSON, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        let result = try await CopilotEnvironment.fetchModels(token: "tok-abc", session: session)
        #expect(result.catalog.models.map(\.id) == ["m1"])
        #expect(result.host == URL(string: "https://api.individual.githubcopilot.com")!)

        let requests = CopilotMockURLProtocol.captured()
        let firstRequest = try #require(requests.first)
        #expect(firstRequest.value(forHTTPHeaderField: "Copilot-Integration-Id") == "copilot-developer-cli")
        #expect(firstRequest.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-07-01")
        #expect(firstRequest.value(forHTTPHeaderField: "Authorization") == "Bearer tok-abc")
    }

    @Test("fetchModels retains picker-disabled models from successful individual catalog")
    func fetchModelsRetainsPickerDisabledIndividualCatalog() async throws {
        let disabledJSON = """
        {
          "data": [
            {
              "id": "d1",
              "name": "Disabled1",
              "model_picker_enabled": false
            },
            {
              "id": "d2",
              "name": "Disabled2",
              "model_picker_enabled": false
            }
          ]
        }
        """.data(using: .utf8)!
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, disabledJSON, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        let result = try await CopilotEnvironment.fetchModels(token: "tok", session: session)
        #expect(result.catalog.models.map(\.id) == ["d1", "d2"])
        #expect(result.host == URL(string: "https://api.individual.githubcopilot.com")!)

        let hosts = CopilotMockURLProtocol.captured().compactMap { $0.url?.host }
        #expect(hosts == ["api.individual.githubcopilot.com"])
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
        let result = try await CopilotEnvironment.fetchModels(token: "tok", session: session)
        #expect(result.catalog.models.map(\.id) == ["from-fallback"])
    }

    @Test(
        "fetchModels falls back once for eligible individual-host failures",
        arguments: CatalogFallbackFailure.allCases
    )
    func fetchModelsFallsBackOnceForEligibleIndividualFailure(_ failure: CatalogFallbackFailure) async throws {
        CopilotMockURLProtocol.reset()
        let businessJSON = """
        { "data": [ { "id": "business-model", "name": "Business Model" } ] }
        """.data(using: .utf8)!

        CopilotMockURLProtocol.setHandler { request in
            let url = request.url!
            if url.host == "api.githubcopilot.com" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, businessJSON, nil)
            }

            switch failure {
            case .transport:
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(), URLError(.timedOut))
            case .notFound:
                let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data(), nil)
            case .serverError:
                let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data(), nil)
            case .malformedJSON:
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("{".utf8), nil)
            case .noNonEmbeddingModels:
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = Data("{\"data\":[{\"id\":\"text-embedding-3-small\"}]}".utf8)
                return (response, data, nil)
            }
        }

        let result = try await CopilotEnvironment.fetchModels(
            token: "tok",
            session: CopilotMockURLProtocol.makeSession()
        )

        #expect(result.host == URL(string: "https://api.githubcopilot.com")!)
        #expect(result.catalog.models.map(\.id) == ["business-model"])
        let businessRequests = CopilotMockURLProtocol.captured().filter {
            $0.url?.host == "api.githubcopilot.com" && $0.url?.path == "/models"
        }
        #expect(businessRequests.count == 1)
    }

    @Test("fetchModels propagates cancellation without host fallback")
    func fetchModelsPropagatesCancellationWithoutFallback() async {
        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(), URLError(.cancelled))
        }

        do {
            _ = try await CopilotEnvironment.fetchModels(
                token: "tok",
                session: CopilotMockURLProtocol.makeSession()
            )
            Issue.record("Expected cancellation to propagate")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(CopilotMockURLProtocol.captured().compactMap(\.url?.host) == [
            "api.individual.githubcopilot.com"
        ])
    }

    @Test(
        "fetchModels surfaces terminal client errors without host fallback",
        arguments: TerminalCatalogStatus.allCases
    )
    func fetchModelsSurfacesTerminalClientErrors(_ status: TerminalCatalogStatus) async {
        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status.rawValue,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("{\"error\":{\"message\":\"safe failure\"}}".utf8)
            return (response, data, nil)
        }

        do {
            _ = try await CopilotEnvironment.fetchModels(
                token: "tok",
                session: CopilotMockURLProtocol.makeSession()
            )
            Issue.record("Expected terminal catalog error")
        } catch TranslationError.apiError(let error) {
            #expect(error.statusCode == status.rawValue)
            #expect(error.localizedSummary.contains("safe failure"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(CopilotMockURLProtocol.captured().compactMap(\.url?.host) == [
            "api.individual.githubcopilot.com"
        ])
    }

    @Test("fetchModels throws final host failure but permits an empty compatible set")
    func fetchModelsDistinguishesFinalFailureFromEmptyCompatibleSet() async throws {
        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"error\":{\"message\":\"final host failure\"}}".utf8)
            return (response, data, nil)
        }

        do {
            _ = try await CopilotEnvironment.fetchModels(
                token: "tok",
                session: CopilotMockURLProtocol.makeSession()
            )
            Issue.record("Expected the final host failure")
        } catch TranslationError.apiError(let error) {
            #expect(error.statusCode == 500)
            #expect(error.localizedSummary.contains("final host failure"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(CopilotMockURLProtocol.captured().count == 2)

        CopilotMockURLProtocol.reset()
        let responsesOnlyJSON = """
        {
          "data": [
            {
              "id": "responses-only",
              "name": "Responses Only",
              "supported_endpoints": ["/responses"]
            }
          ]
        }
        """.data(using: .utf8)!
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responsesOnlyJSON, nil)
        }

        let result = try await CopilotEnvironment.fetchModels(
            token: "tok",
            session: CopilotMockURLProtocol.makeSession()
        )
        #expect(result.catalog.autoHintModelIDs.isEmpty)
        #expect(result.catalog.models.map(\.id) == ["responses-only"])
    }

    @Test("catalog selection applies operation-specific host policies without merging")
    func catalogSelectionAppliesOperationSpecificHostPolicies() async throws {
        let responsesOnly = Data("{\"data\":[{\"id\":\"responses-only\",\"name\":\"Responses Only\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/responses\"]}]}".utf8)
        let autoCompatible = Data("{\"data\":[{\"id\":\"business-auto\",\"name\":\"Business Auto\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)

        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let data = request.url?.host == "api.individual.githubcopilot.com" ? responsesOnly : autoCompatible
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data, nil)
        }
        let autoResult = try await CopilotEnvironment.selectCatalog(
            token: "tok",
            purpose: .auto,
            session: CopilotMockURLProtocol.makeSession(),
            store: CopilotModelCatalogStore()
        )
        #expect(autoResult.host.host == "api.githubcopilot.com")
        #expect(autoResult.catalog.models.map(\.id) == ["business-auto"])

        let otherModel = Data("{\"data\":[{\"id\":\"other\",\"name\":\"Other\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let targetModel = Data("{\"data\":[{\"id\":\"target\",\"name\":\"Target\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let data = request.url?.host == "api.individual.githubcopilot.com" ? otherModel : targetModel
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data, nil)
        }
        let explicitResult = try await CopilotEnvironment.selectCatalog(
            token: "tok",
            purpose: .explicit(modelID: "target"),
            session: CopilotMockURLProtocol.makeSession(),
            store: CopilotModelCatalogStore()
        )
        #expect(explicitResult.host.host == "api.githubcopilot.com")
        #expect(explicitResult.catalog.models.map(\.id) == ["target"])

        let individualAutoOnly = Data("{\"data\":[{\"id\":\"individual-auto\",\"name\":\"Individual Auto\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        for businessFails in [false, true] {
            CopilotMockURLProtocol.reset()
            CopilotMockURLProtocol.setHandler { request in
                let isBusiness = request.url?.host == "api.githubcopilot.com"
                let status = isBusiness && businessFails ? 500 : 200
                let data = isBusiness ? responsesOnly : individualAutoOnly
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (response, data, nil)
            }
            let settingsResult = try await CopilotEnvironment.selectCatalog(
                token: "tok",
                purpose: .settings,
                session: CopilotMockURLProtocol.makeSession(),
                store: CopilotModelCatalogStore()
            )
            #expect(settingsResult.host.host == "api.individual.githubcopilot.com")
            #expect(settingsResult.catalog.models.map(\.id) == ["individual-auto"])
        }
    }

    @Test("catalog store shares entries across operations before the exact TTL")
    func catalogStoreSharesEntriesAcrossOperationsBeforeExactTTL() async throws {
        CopilotMockURLProtocol.reset()
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
        let store = CopilotModelCatalogStore(now: clock.now)
        let compatibleJSON = Data("{\"data\":[{\"id\":\"compatible\",\"name\":\"Compatible\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, compatibleJSON, nil)
        }
        let session = CopilotMockURLProtocol.makeSession()

        _ = try await CopilotEnvironment.selectCatalog(
            token: "same-account",
            purpose: .settings,
            session: session,
            store: store
        )
        _ = try await CopilotEnvironment.selectCatalog(
            token: "same-account",
            purpose: .auto,
            session: session,
            store: store
        )
        #expect(CopilotMockURLProtocol.captured().count == 1)

        clock.advance(by: 300)
        _ = try await CopilotEnvironment.selectCatalog(
            token: "same-account",
            purpose: .auto,
            session: session,
            store: store
        )
        #expect(CopilotMockURLProtocol.captured().count == 2)
    }

    @Test("catalog store single-flights requests and isolates account state")
    func catalogStoreSingleFlightsRequestsAndIsolatesAccountState() async throws {
        let compatibleJSON = Data("{\"data\":[{\"id\":\"compatible\",\"name\":\"Compatible\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)

        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            Thread.sleep(forTimeInterval: 0.05)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, compatibleJSON, nil)
        }
        let concurrentStore = CopilotModelCatalogStore()
        let concurrentSession = CopilotMockURLProtocol.makeSession()
        async let first = CopilotEnvironment.selectCatalog(
            token: "same-account",
            purpose: .auto,
            session: concurrentSession,
            store: concurrentStore
        )
        async let second = CopilotEnvironment.selectCatalog(
            token: "same-account",
            purpose: .settings,
            session: concurrentSession,
            store: concurrentStore
        )
        _ = try await (first, second)
        #expect(CopilotMockURLProtocol.captured().count == 1)

        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data(), nil)
        }
        let failureStore = CopilotModelCatalogStore()
        let failureSession = CopilotMockURLProtocol.makeSession()
        await #expect(throws: TranslationError.self) {
            _ = try await CopilotEnvironment.selectCatalog(
                token: "failure-account",
                purpose: .auto,
                session: failureSession,
                store: failureStore
            )
        }
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, compatibleJSON, nil)
        }
        _ = try await CopilotEnvironment.selectCatalog(
            token: "failure-account",
            purpose: .auto,
            session: failureSession,
            store: failureStore
        )
        #expect(CopilotMockURLProtocol.captured().count == 3)

        CopilotMockURLProtocol.reset()
        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, compatibleJSON, nil)
        }
        let accountStore = CopilotModelCatalogStore()
        let accountSession = CopilotMockURLProtocol.makeSession()
        for token in ["account-a", "account-b", "account-a"] {
            _ = try await CopilotEnvironment.selectCatalog(
                token: token,
                purpose: .auto,
                session: accountSession,
                store: accountStore
            )
        }
        #expect(CopilotMockURLProtocol.captured().count == 3)
    }

    @Test("fetchModels fails when endpoints have no non-embedding models")
    func fetchModelsFailsWithoutNonEmbeddingModels() async {
        let embeddingOnlyJSON = """
        { "data": [ { "id": "text-embedding-3-small", "name": "Embedding" } ] }
        """.data(using: .utf8)!

        CopilotMockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, embeddingOnlyJSON, nil)
        }

        let session = CopilotMockURLProtocol.makeSession()
        await #expect(throws: TranslationError.self) {
            _ = try await CopilotEnvironment.fetchModels(token: "tok", session: session)
        }
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

@Suite("SettingsView Copilot")
struct SettingsViewCopilotTests {
    @Test("Auto-only state renders the shared enabled Picker with only Auto")
    func autoOnlyStateRendersSingleOptionPicker() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MangaTranslator/Views/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try #require(source.range(of: "case .autoOnly:"))
        let end = try #require(source.range(of: "case .selectable", range: start.upperBound..<source.endIndex))
        let branch = String(source[start.lowerBound..<end.lowerBound])

        #expect(source.contains("Label(\"Copilot CLI detected\", systemImage: \"checkmark.circle.fill\")"))
        #expect(branch.contains("copilotModelPicker(models: [.auto])"))
        #expect(!branch.contains("LabeledContent("))
        #expect(!branch.contains("GitHub selects a compatible model automatically."))
        #expect(!branch.contains(".disabled("))
    }

    @Test("Selectable state renders Auto first and only compatible picker models")
    func selectableStateRendersFilteredPickerWithAutoFirst() throws {
        let catalog = CopilotModelCatalog(models: [
            CopilotModel(id: "disabled", name: "Disabled", category: nil, pickerEnabled: false, supportedEndpoints: ["/chat/completions"]),
            CopilotModel(id: "responses", name: "Responses", category: nil, pickerEnabled: true, supportedEndpoints: ["/responses"]),
            CopilotModel(id: "zeta", name: "Zeta", category: nil, pickerEnabled: true, supportedEndpoints: ["/chat/completions"]),
            CopilotModel(id: "alpha", name: "Alpha", category: nil, pickerEnabled: true, supportedEndpoints: ["/chat/completions"])
        ])
        guard case .selectable(let models) = CopilotModelLoadState.loaded(from: catalog) else {
            Issue.record("Expected selectable state")
            return
        }
        #expect(models.map(\.id) == ["auto", "alpha", "zeta"])

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MangaTranslator/Views/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try #require(source.range(of: "case .selectable(let models):"))
        let end = try #require(source.range(of: "case .noCompatibleModels:", range: start.upperBound..<source.endIndex))
        let branch = String(source[start.lowerBound..<end.lowerBound])
        #expect(branch.contains("copilotModelPicker(models: models)"))
        #expect(source.contains("Picker(\"Model\", selection: $preferences.copilotModel)"))
        #expect(source.contains("ForEach(models)"))
        #expect(source.contains("Text(model.displayLabel).tag(model.id)"))
    }

    @Test("Loading, no-compatible, and failed states render distinct retryable UI")
    func loadingNoCompatibleAndFailedStatesRenderDistinctRetryableUI() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MangaTranslator/Views/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("ProgressView(\"Checking models…\")"))
        #expect(source.contains("Text(\"No compatible Copilot models available.\")"))
        #expect(source.contains("Text(\"Couldn’t load Copilot models.\")"))
        #expect(source.contains("Button(\"Retry\")"))
        #expect(source.contains("copilotModelState = .loading"))
        #expect(source.contains("await loadCopilotModels(token: token)"))
    }
}
