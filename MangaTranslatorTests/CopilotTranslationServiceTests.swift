import Testing
import Foundation
@testable import MangaTranslator

enum InvalidAutoSessionCase: CaseIterable, Sendable {
    case missingSelectedModel
    case missingSessionToken
    case emptySessionToken
    case invalidExpiry
    case nonfutureExpiry
    case selectedAbsentFromAvailable
    case selectedOutsideHints
}

enum FatalRefreshCase: CaseIterable, Sendable {
    case rateLimited
    case forbidden
    case badRequest
    case malformedSuccess
    case invalidSelection
}

enum UnavailableExplicitModelCase: CaseIterable, Sendable {
    case absent
    case pickerDisabled
    case responsesOnly
    case missingEndpoint
}

enum RecoverableAutoErrorCode: String, CaseIterable, Sendable {
    case modelNotSupported = "model_not_supported"
    case unsupportedAPI = "unsupported_api_for_model"
}

enum TerminalExplicitStatus: Int, CaseIterable, Sendable {
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case rateLimited = 429
}

actor CopilotAsyncTestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func hasWaiter() -> Bool {
        continuation != nil
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

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

    @Test("Auto translation resolves a compatible model session before inference")
    func autoTranslationResolvesCompatibleModelSessionBeforeInference() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data(#"""
        {"data":[
          {"id":"gpt-5-mini","name":"GPT-5 mini","model_picker_enabled":false,"supported_endpoints":["/chat/completions"]},
          {"id":"gpt-5.3-codex","name":"GPT-5.3 Codex","model_picker_enabled":false,"supported_endpoints":["/responses"]}
        ]}
        """#.utf8)
        let sessionJSON = Data(#"""
        {"selected_model":"gpt-5-mini","available_models":["gpt-5-mini"],"session_token":"session-secret","expires_at":4102444800}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            switch request.url?.path {
            case "/models":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
            case "/models/session":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, sessionJSON)
            case "/chat/completions":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, validSinglePageResponseBody(translation: "Translated"))
            default:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )
        let output = try await service.translate(
            bubbles: [makeSingleBubble()],
            from: .ja,
            to: .en,
            context: .empty,
            token: "oauth-token"
        )

        #expect(output.bubbles.first?.translatedText == "Translated")
        #expect(counter.capturedRequests.compactMap(\.url?.path) == [
            "/models", "/models/session", "/chat/completions"
        ])
        let modelSessionRequest = try #require(counter.capturedRequests.first { $0.url?.path == "/models/session" })
        let modelSessionBody = String(decoding: modelSessionRequest.readMockBody(), as: UTF8.self)
        #expect(modelSessionBody.contains("gpt-5-mini"))
        #expect(!modelSessionBody.contains("gpt-5.3-codex"))

        let inferenceRequest = try #require(counter.capturedRequests.first { $0.url?.path == "/chat/completions" })
        let inferenceBody = String(decoding: inferenceRequest.readMockBody(), as: UTF8.self)
        #expect(inferenceBody.contains("\"model\":\"gpt-5-mini\""))
        #expect(!inferenceBody.contains("\"model\":\"auto\""))
        #expect(inferenceRequest.value(forHTTPHeaderField: "Copilot-Session-Token") == "session-secret")
        #expect(inferenceRequest.value(forHTTPHeaderField: "Copilot-Integration-Id") == "copilot-developer-cli")
        #expect(inferenceRequest.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-07-01")
    }

    @Test("Explicit compatible model is catalog-validated and sent without an Auto session")
    func explicitCompatibleModelIsValidatedAndSentDirectly() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/models" { return (response, modelsJSON) }
            return (response, validSinglePageResponseBody(translation: "Explicit"))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "gpt-5-mini",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        let output = try await service.translate(
            bubbles: [makeSingleBubble()], from: .ja, to: .en,
            context: .empty, token: "oauth-token"
        )

        #expect(output.bubbles.first?.translatedText == "Explicit")
        #expect(counter.capturedRequests.compactMap(\.url?.path) == ["/models", "/chat/completions"])
        let inference = try #require(counter.capturedRequests.last)
        #expect(inference.value(forHTTPHeaderField: "Copilot-Session-Token") == nil)
        #expect(String(decoding: inference.readMockBody(), as: UTF8.self).contains("\"model\":\"gpt-5-mini\""))
    }

    @Test(
        "Unavailable explicit models fail before inference without switching to Auto",
        arguments: UnavailableExplicitModelCase.allCases
    )
    func unavailableExplicitModelsFailBeforeInference(_ testCase: UnavailableExplicitModelCase) async {
        let counter = BatchRequestCounter()
        let modelJSON: String = switch testCase {
        case .absent:
            "{\"id\":\"other\",\"name\":\"Other\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}"
        case .pickerDisabled:
            "{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}"
        case .responsesOnly:
            "{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/responses\"]}"
        case .missingEndpoint:
            "{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":true}"
        }
        let modelsJSON = Data("{\"data\":[\(modelJSON)]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                modelsJSON
            )
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "gpt-5-mini", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        await #expect(throws: CopilotCatalogSelectionError.modelUnavailable("gpt-5-mini")) {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()], from: .ja, to: .en,
                context: .empty, token: "oauth-token"
            )
        }
        #expect(counter.capturedRequests.compactMap(\.url?.path) == ["/models", "/models"])
        #expect(!counter.capturedRequests.contains { $0.url?.path == "/models/session" || $0.url?.path == "/chat/completions" })
    }

    @Test("Explicit inference fallback revalidates the model on the business host")
    func explicitInferenceFallbackRevalidatesBusinessCatalog() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            if request.url?.path == "/models" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
            }
            if request.url?.host == "api.individual.githubcopilot.com" {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                validSinglePageResponseBody(translation: "Business")
            )
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "gpt-5-mini", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        let output = try await service.translate(
            bubbles: [makeSingleBubble()], from: .ja, to: .en,
            context: .empty, token: "oauth-token"
        )

        #expect(output.bubbles.first?.translatedText == "Business")
        #expect(counter.capturedRequests.compactMap { request in
            guard let host = request.url?.host, let path = request.url?.path else { return nil }
            return host + path
        } == [
            "api.individual.githubcopilot.com/models",
            "api.individual.githubcopilot.com/chat/completions",
            "api.individual.githubcopilot.com/chat/completions",
            "api.githubcopilot.com/models",
            "api.githubcopilot.com/chat/completions"
        ])
        #expect(!counter.capturedRequests.contains { $0.url?.path == "/models/session" })
        #expect(counter.capturedRequests.allSatisfy {
            $0.value(forHTTPHeaderField: "Copilot-Session-Token") == nil
        })
    }

    @Test("Auto model incompatibility invalidates once and retries with a new session model")
    func autoModelIncompatibilityRecoversOnceWithNewSession() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"model-a\",\"name\":\"Model A\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]},{\"id\":\"model-b\",\"name\":\"Model B\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/models" { return (response, modelsJSON) }
            if request.url?.path == "/models/session" {
                let attempt = counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count
                let model = attempt == 1 ? "model-a" : "model-b"
                let body = Data("{\"selected_model\":\"\(model)\",\"available_models\":[\"model-a\",\"model-b\"],\"session_token\":\"session-\(attempt)\",\"expires_at\":4102444800}".utf8)
                return (response, body)
            }
            let inferenceAttempt = counter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count
            if inferenceAttempt == 1 {
                let body = Data("{\"error\":{\"message\":\"unsupported\",\"code\":\"model_not_supported\"}}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
            }
            return (response, validSinglePageResponseBody(translation: "Recovered"))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        let output = try await service.translate(
            bubbles: [makeSingleBubble()], from: .ja, to: .en,
            context: .empty, token: "oauth-token"
        )

        #expect(output.bubbles.first?.translatedText == "Recovered")
        let sessions = counter.capturedRequests.filter { $0.url?.path == "/models/session" }
        let inferences = counter.capturedRequests.filter { $0.url?.path == "/chat/completions" }
        #expect(sessions.count == 2)
        #expect(inferences.count == 2)
        #expect(String(decoding: inferences[0].readMockBody(), as: UTF8.self).contains("\"model\":\"model-a\""))
        #expect(String(decoding: inferences[1].readMockBody(), as: UTF8.self).contains("\"model\":\"model-b\""))
    }

    @Test(
        "Repeated Auto compatibility errors stop after one recovery",
        arguments: RecoverableAutoErrorCode.allCases
    )
    func repeatedAutoCompatibilityErrorsStopAfterOneRecovery(_ errorCode: RecoverableAutoErrorCode) async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"model-a\",\"name\":\"Model A\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            if request.url?.path == "/models" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
            }
            if request.url?.path == "/models/session" {
                let body = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\"],\"session_token\":\"new-session\",\"expires_at\":4102444800}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            let body = Data("{\"error\":{\"message\":\"unsupported\",\"code\":\"\(errorCode.rawValue)\"}}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        do {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()], from: .ja, to: .en,
                context: .empty, token: "oauth-token"
            )
            Issue.record("Expected repeated compatibility error")
        } catch TranslationError.apiError(let error) {
            #expect(error.code == errorCode.rawValue)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 2)
        #expect(counter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count == 2)
    }

    @Test("Auto inference 401 reacquires once without the old session token")
    func autoInference401ReacquiresOnceAndKeepsOAuthFailuresTerminal() async throws {
        func run(acquisitionFailureStatus: Int?) async throws -> (BatchRequestCounter, TranslationOutput?) {
            let counter = BatchRequestCounter()
            let modelsJSON = Data("{\"data\":[{\"id\":\"model-a\",\"name\":\"Model A\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
            let session = ProviderHTTPMockURLProtocol.makeSession { request in
                _ = counter.record(request: request)
                if request.url?.path == "/models" {
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
                }
                if request.url?.path == "/models/session" {
                    let attempt = counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count
                    if attempt == 2, let acquisitionFailureStatus {
                        return (HTTPURLResponse(url: request.url!, statusCode: acquisitionFailureStatus, httpVersion: nil, headerFields: nil)!, Data())
                    }
                    let body = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\"],\"session_token\":\"session-\(attempt)\",\"expires_at\":4102444800}".utf8)
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
                }
                let attempt = counter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count
                if attempt == 1 {
                    return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
                }
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    validSinglePageResponseBody(translation: "Reauthorized")
                )
            }
            defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
            let service = CopilotTranslationService(
                model: "auto", urlSession: session,
                catalogStore: CopilotModelCatalogStore(),
                sessionResolver: CopilotAutoSessionResolver()
            )
            do {
                let output = try await service.translate(
                    bubbles: [makeSingleBubble()], from: .ja, to: .en,
                    context: .empty, token: "oauth-token"
                )
                return (counter, output)
            } catch {
                if acquisitionFailureStatus == nil { throw error }
                return (counter, nil)
            }
        }

        let (successCounter, output) = try await run(acquisitionFailureStatus: nil)
        #expect(output?.bubbles.first?.translatedText == "Reauthorized")
        let successSessions = successCounter.capturedRequests.filter { $0.url?.path == "/models/session" }
        #expect(successSessions.count == 2)
        let reacquisition = try #require(successSessions.last)
        #expect(reacquisition.value(forHTTPHeaderField: "Copilot-Session-Token") == nil)
        #expect(successCounter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count == 2)

        for status in [401, 403] {
            let (failureCounter, output) = try await run(acquisitionFailureStatus: status)
            #expect(output == nil)
            #expect(failureCounter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 2)
            #expect(failureCounter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count == 1)
            #expect(!failureCounter.capturedRequests.contains { $0.url?.host == "api.githubcopilot.com" })
        }
    }

    @Test("Auto recovery causes share one per-translation budget")
    func autoRecoveryCausesShareOneBudget() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"model-a\",\"name\":\"Model A\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            if request.url?.path == "/models" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
            }
            if request.url?.path == "/models/session" {
                let body = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\"],\"session_token\":\"session\",\"expires_at\":4102444800}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            let attempt = counter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count
            let status = attempt == 1 ? 400 : 401
            let code = attempt == 1 ? "model_not_supported" : "unauthorized"
            let body = Data("{\"error\":{\"message\":\"failed\",\"code\":\"\(code)\"}}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        await #expect(throws: TranslationError.self) {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()], from: .ja, to: .en,
                context: .empty, token: "oauth-token"
            )
        }
        #expect(counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 2)
        #expect(counter.capturedRequests.filter { $0.url?.path == "/chat/completions" }.count == 2)
    }

    @Test("Auto protocol fallback starts a clean transaction on the business host")
    func autoProtocolFallbackUsesHostLocalCatalogAndSession() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"model-a\",\"name\":\"Model A\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/models" { return (response, modelsJSON) }
            if request.url?.path == "/models/session" {
                if request.url?.host == "api.individual.githubcopilot.com" {
                    return (response, Data("{}".utf8))
                }
                let body = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\"],\"session_token\":\"business-session\",\"expires_at\":4102444800}".utf8)
                return (response, body)
            }
            return (response, validSinglePageResponseBody(translation: "Business"))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        let output = try await service.translate(
            bubbles: [makeSingleBubble()], from: .ja, to: .en,
            context: .empty, token: "oauth-token"
        )

        #expect(output.bubbles.first?.translatedText == "Business")
        #expect(counter.capturedRequests.compactMap { request in
            guard let host = request.url?.host, let path = request.url?.path else { return nil }
            return host + path
        } == [
            "api.individual.githubcopilot.com/models",
            "api.individual.githubcopilot.com/models/session",
            "api.githubcopilot.com/models",
            "api.githubcopilot.com/models/session",
            "api.githubcopilot.com/chat/completions"
        ])
        let businessRequests = counter.capturedRequests.filter { $0.url?.host == "api.githubcopilot.com" }
        #expect(!businessRequests.contains {
            $0.value(forHTTPHeaderField: "Copilot-Session-Token")?.contains("individual") == true
        })
    }

    @Test(
        "Explicit terminal inference errors are sent once without fallback",
        arguments: TerminalExplicitStatus.allCases
    )
    func explicitTerminalInferenceErrorsAreSentOnce(_ terminalStatus: TerminalExplicitStatus) async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            if request.url?.path == "/models" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
            }
            let body = Data("{\"error\":{\"message\":\"terminal\",\"code\":\"terminal\"}}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: terminalStatus.rawValue, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "gpt-5-mini", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        do {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()], from: .ja, to: .en,
                context: .empty, token: "oauth-token"
            )
            Issue.record("Expected terminal error")
        } catch TranslationError.apiError(let error) {
            #expect(error.statusCode == terminalStatus.rawValue)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(counter.capturedRequests.compactMap(\.url?.path) == ["/models", "/chat/completions"])
        #expect(!counter.capturedRequests.contains { $0.url?.host == "api.githubcopilot.com" })
        #expect(!counter.capturedRequests.contains { $0.url?.path == "/models/session" })
    }

    @Test("Successful Auto routing logs only the resolved model and sanitized endpoint")
    func successfulAutoRoutingLogsAllowlistedMetadataOnly() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = DebugLogStore(databaseURL: tempURL)
        let logger = DebugLogger(store: store)
        let modelsJSON = Data("{\"data\":[{\"id\":\"model-a\",\"name\":\"Model A\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let sessionJSON = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\"],\"session_token\":\"session-secret-value\",\"expires_at\":4102444800}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/models": return (response, modelsJSON)
            case "/models/session": return (response, sessionJSON)
            default: return (response, validSinglePageResponseBody(translation: "Logged"))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto", urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver(),
            debugLogger: logger
        )

        _ = try await service.translate(
            bubbles: [makeSingleBubble()], from: .ja, to: .en,
            context: .empty, token: "oauth-secret-value"
        )
        await logger.flush()

        let entries = await store.query(filter: DebugLogFilter())
        let routingEntry = try #require(entries.first { $0.message.contains("Translation started") })
        let metadata = try JSONDecoder().decode([String: String].self, from: Data(routingEntry.metadataJSON.utf8))
        #expect(metadata == [
            "model": "model-a",
            "endpoint": "https://api.individual.githubcopilot.com"
        ])
        let persisted = entries.map { $0.message + $0.metadataJSON }.joined(separator: "\n")
        #expect(!persisted.contains("oauth-secret-value"))
        #expect(!persisted.contains("session-secret-value"))
        #expect(!persisted.contains("selected_model"))
        #expect(!persisted.contains("messages"))
    }

    @Test("Model-session errors redact credentials in UI and persisted diagnostics")
    func modelSessionErrorsAreSanitizedBeforeDisplayAndPersistence() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = DebugLogStore(databaseURL: tempURL)
        let logger = DebugLogger(store: store)
        let opaque = String(repeating: "a", count: 80)
        let responseBody = Data("{\"error\":{\"message\":\"Authorization: Bearer ghu_secret1234567890abcdef user@example.com token=query-secret \(opaque)\",\"code\":\"session_failed\"}}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                responseBody
            )
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let resolver = CopilotAutoSessionResolver(debugLogger: logger)

        do {
            _ = try await resolver.resolve(
                token: "oauth-secret", host: CopilotEnvironment.individualHost,
                modelHints: ["model-a"], urlSession: session
            )
            Issue.record("Expected model-session failure")
        } catch TranslationError.apiError(let error) {
            #expect(error.message?.count ?? 0 <= APIErrorSanitizer.maxMessageLength)
            let description = error.localizedSummary
            #expect(!description.contains("ghu_secret"))
            #expect(!description.contains("user@example.com"))
            #expect(!description.contains("query-secret"))
            #expect(!description.contains(opaque))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await logger.flush()
        let persisted = await store.query(filter: DebugLogFilter())
        let text = persisted.map { $0.message + $0.metadataJSON }.joined(separator: "\n")
        #expect(!text.contains("ghu_secret"))
        #expect(!text.contains("user@example.com"))
        #expect(!text.contains("query-secret"))
        #expect(!text.contains(opaque))
        #expect(!text.contains("Authorization"))
    }

    @Test(
        "Invalid Auto session responses never reach inference",
        arguments: InvalidAutoSessionCase.allCases
    )
    func invalidAutoSessionResponsesNeverReachInference(_ testCase: InvalidAutoSessionCase) async {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let sessionBody: Data
        switch testCase {
        case .missingSelectedModel:
            sessionBody = Data("{\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"token\",\"expires_at\":4102444800}".utf8)
        case .missingSessionToken:
            sessionBody = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"expires_at\":4102444800}".utf8)
        case .emptySessionToken:
            sessionBody = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"\",\"expires_at\":4102444800}".utf8)
        case .invalidExpiry:
            sessionBody = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"token\",\"expires_at\":\"invalid\"}".utf8)
        case .nonfutureExpiry:
            sessionBody = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"token\",\"expires_at\":0}".utf8)
        case .selectedAbsentFromAvailable:
            sessionBody = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"other\"],\"session_token\":\"token\",\"expires_at\":4102444800}".utf8)
        case .selectedOutsideHints:
            sessionBody = Data("{\"selected_model\":\"other\",\"available_models\":[\"other\"],\"session_token\":\"token\",\"expires_at\":4102444800}".utf8)
        }
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/models": return (response, modelsJSON)
            case "/models/session": return (response, sessionBody)
            default: return (response, validSinglePageResponseBody(translation: "Must not infer"))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        await #expect(throws: Error.self) {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()],
                from: .ja,
                to: .en,
                context: .empty,
                token: "oauth-token"
            )
        }
        #expect(!counter.capturedRequests.contains { $0.url?.path == "/chat/completions" })
    }

    @Test("Expiry-less Auto sessions are immediate-use only")
    func expirylessAutoSessionsAreImmediateUseOnly() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let sessionJSON = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"one-use\"}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/models": return (response, modelsJSON)
            case "/models/session": return (response, sessionJSON)
            default: return (response, validSinglePageResponseBody(translation: "Translated"))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        for _ in 0..<2 {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()],
                from: .ja,
                to: .en,
                context: .empty,
                token: "oauth-token"
            )
        }
        #expect(counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 2)
    }

    @Test("Fresh Auto session is reused across public translations")
    func freshAutoSessionIsReusedAcrossPublicTranslations() async throws {
        let counter = BatchRequestCounter()
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let expiry = Int(clock.now().timeIntervalSince1970 + 600)
        let sessionJSON = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"cached\",\"expires_at\":\(expiry)}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/models": return (response, modelsJSON)
            case "/models/session": return (response, sessionJSON)
            default: return (response, validSinglePageResponseBody(translation: "Translated"))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(now: clock.now),
            sessionResolver: CopilotAutoSessionResolver(now: clock.now)
        )

        for _ in 0..<2 {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()],
                from: .ja,
                to: .en,
                context: .empty,
                token: "oauth-token"
            )
        }
        #expect(counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 1)
    }

    @Test("Auto session cache honors reuse refresh and expiry boundaries")
    func autoSessionCacheHonorsReuseRefreshAndExpiryBoundaries() async throws {
        let counter = BatchRequestCounter()
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/models" { return (response, modelsJSON) }
            if request.url?.path == "/models/session" {
                let attempt = counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count
                let values: (String, Int) = switch attempt {
                case 1: ("old-token", 1_401)
                case 2: ("refreshed-token", 1_600)
                default: ("new-token", 2_200)
                }
                let body = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"\(values.0)\",\"expires_at\":\(values.1)}".utf8)
                return (response, body)
            }
            return (response, validSinglePageResponseBody(translation: "Translated"))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(now: clock.now),
            sessionResolver: CopilotAutoSessionResolver(now: clock.now)
        )
        func translate() async throws {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()], from: .ja, to: .en,
                context: .empty, token: "oauth-token"
            )
        }

        try await translate()
        clock.advance(by: 100)
        try await translate()
        #expect(counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 1)

        clock.advance(by: 1)
        try await translate()
        var sessionRequests = counter.capturedRequests.filter { $0.url?.path == "/models/session" }
        #expect(sessionRequests.count == 2)
        let initialRequest = try #require(sessionRequests.first)
        let refreshRequest = try #require(sessionRequests.dropFirst().first)
        #expect(refreshRequest.value(forHTTPHeaderField: "Copilot-Session-Token") == "old-token")
        #expect(refreshRequest.readMockBody() == initialRequest.readMockBody())

        clock.advance(by: 500)
        try await translate()
        sessionRequests = counter.capturedRequests.filter { $0.url?.path == "/models/session" }
        #expect(sessionRequests.count == 3)
        let expiredAcquisition = try #require(sessionRequests.last)
        #expect(expiredAcquisition.value(forHTTPHeaderField: "Copilot-Session-Token") == nil)
    }

    @Test("Refresh atomically replaces sessions and expiry-less refresh clears cache")
    func refreshAtomicallyReplacesSessionsAndExpirylessRefreshClearsCache() async throws {
        let host = URL(string: "https://api.individual.githubcopilot.com")!
        let hints = ["model-a", "model-b"]
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))

        let replacementCounter = BatchRequestCounter()
        let replacementSession = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = replacementCounter.record(request: request)
            let attempt = replacementCounter.count
            let values = attempt == 1
                ? ("model-a", "token-a", 1_200)
                : ("model-b", "token-b", 2_000)
            let body = Data("{\"selected_model\":\"\(values.0)\",\"available_models\":[\"model-a\",\"model-b\"],\"session_token\":\"\(values.1)\",\"expires_at\":\(values.2)}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(replacementSession) }
        let replacementResolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await replacementResolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: replacementSession)
        let replacement = try await replacementResolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: replacementSession)
        let reused = try await replacementResolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: replacementSession)
        #expect(replacement.modelID == "model-b")
        #expect(replacement.sessionToken == "token-b")
        #expect(reused.modelID == "model-b")
        #expect(replacementCounter.count == 2)

        let expirylessCounter = BatchRequestCounter()
        let expirylessSession = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = expirylessCounter.record(request: request)
            let attempt = expirylessCounter.count
            let body: Data
            switch attempt {
            case 1:
                body = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\",\"model-b\"],\"session_token\":\"old-token\",\"expires_at\":1200}".utf8)
            case 2:
                body = Data("{\"selected_model\":\"model-b\",\"available_models\":[\"model-a\",\"model-b\"],\"session_token\":\"one-use\"}".utf8)
            default:
                body = Data("{\"selected_model\":\"model-a\",\"available_models\":[\"model-a\",\"model-b\"],\"session_token\":\"new-token\",\"expires_at\":2000}".utf8)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(expirylessSession) }
        let expirylessResolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await expirylessResolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: expirylessSession)
        let immediate = try await expirylessResolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: expirylessSession)
        _ = try await expirylessResolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: expirylessSession)
        #expect(immediate.modelID == "model-b")
        #expect(immediate.expiresAt == nil)
        let requests = expirylessCounter.capturedRequests
        #expect(requests.count == 3)
        #expect(requests[1].value(forHTTPHeaderField: "Copilot-Session-Token") == "old-token")
        #expect(requests[2].value(forHTTPHeaderField: "Copilot-Session-Token") == nil)
    }

    @Test("Refresh 401 retries once without the old token and acquisition auth errors are terminal")
    func refresh401RetriesHeaderlessAndAcquisitionAuthErrorsAreTerminal() async throws {
        let host = URL(string: "https://api.individual.githubcopilot.com")!
        let hints = ["gpt-5-mini"]
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let attempt = counter.count
            if attempt == 2 {
                let body = Data("{\"error\":{\"message\":\"expired session\"}}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
            }
            let token = attempt == 1 ? "old-token" : "new-token"
            let expiry = attempt == 1 ? 1_200 : 2_000
            let body = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"\(token)\",\"expires_at\":\(expiry)}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let resolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
        let replacement = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
        #expect(replacement.sessionToken == "new-token")
        #expect(counter.capturedRequests.count == 3)
        #expect(counter.capturedRequests[1].value(forHTTPHeaderField: "Copilot-Session-Token") == "old-token")
        #expect(counter.capturedRequests[2].value(forHTTPHeaderField: "Copilot-Session-Token") == nil)

        for status in [401, 403] {
            let authSession = ProviderHTTPMockURLProtocol.makeSession { request in
                let body = Data("{\"error\":{\"message\":\"authorization failed\"}}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
            }
            defer { ProviderHTTPMockURLProtocol.releaseSession(authSession) }
            do {
                _ = try await CopilotAutoSessionResolver(now: clock.now).resolve(
                    token: "oauth", host: host, modelHints: hints, urlSession: authSession
                )
                Issue.record("Expected authorization failure")
            } catch TranslationError.apiError(let error) {
                #expect(error.statusCode == status)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Transient refresh failure reuses only a still-unexpired session")
    func transientRefreshFailureReusesOnlyStillUnexpiredSession() async throws {
        let host = URL(string: "https://api.individual.githubcopilot.com")!
        let hints = ["gpt-5-mini"]

        for expiryAdvance in [100.0, 300.0] {
            let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
            let counter = BatchRequestCounter()
            let session = ProviderHTTPMockURLProtocol.makeSession { request in
                _ = counter.record(request: request)
                if counter.count == 1 {
                    let body = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"old-token\",\"expires_at\":1200}".utf8)
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
                }
                clock.advance(by: expiryAdvance)
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
            let resolver = CopilotAutoSessionResolver(now: clock.now)
            _ = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)

            if expiryAdvance == 100 {
                let reused = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
                #expect(reused.sessionToken == "old-token")
            } else {
                await #expect(throws: TranslationError.self) {
                    _ = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
                }
            }
            #expect(counter.count == 2)
        }
    }

    @Test(
        "Fatal refresh failures discard the old token",
        arguments: FatalRefreshCase.allCases
    )
    func fatalRefreshFailuresDiscardOldToken(_ testCase: FatalRefreshCase) async throws {
        let host = URL(string: "https://api.individual.githubcopilot.com")!
        let hints = ["gpt-5-mini"]
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let attempt = counter.count
            if attempt == 1 || attempt == 3 {
                let token = attempt == 1 ? "old-token" : "new-token"
                let expiry = attempt == 1 ? 1_200 : 2_000
                let body = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"\(token)\",\"expires_at\":\(expiry)}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            switch testCase {
            case .rateLimited:
                return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data())
            case .forbidden:
                return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
            case .badRequest:
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
            case .malformedSuccess:
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{".utf8))
            case .invalidSelection:
                let body = Data("{\"selected_model\":\"other\",\"available_models\":[\"other\"],\"session_token\":\"invalid\",\"expires_at\":2000}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let resolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
        do {
            _ = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
            Issue.record("Expected refresh failure")
        } catch {}
        _ = try await resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)

        #expect(counter.capturedRequests.count == 3)
        #expect(counter.capturedRequests[1].value(forHTTPHeaderField: "Copilot-Session-Token") == "old-token")
        #expect(counter.capturedRequests[2].value(forHTTPHeaderField: "Copilot-Session-Token") == nil)
    }

    @Test("Concurrent session resolution is single-flight and waiter cancellation is local")
    func concurrentSessionResolutionIsSingleFlightAndWaiterCancellationIsLocal() async throws {
        let host = URL(string: "https://api.individual.githubcopilot.com")!
        let hints = ["gpt-5-mini"]
        let body = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"shared\",\"expires_at\":4102444800}".utf8)

        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            Thread.sleep(forTimeInterval: 0.05)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let resolver = CopilotAutoSessionResolver()
        async let first = resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
        async let second = resolver.resolve(token: "oauth", host: host, modelHints: hints, urlSession: session)
        _ = try await (first, second)
        #expect(counter.count == 1)

        let cancellationCounter = BatchRequestCounter()
        let cancellationSession = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = cancellationCounter.record(request: request)
            Thread.sleep(forTimeInterval: 0.05)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(cancellationSession) }
        let cancellationResolver = CopilotAutoSessionResolver()
        let owner = Task {
            try await cancellationResolver.resolve(
                token: "oauth", host: host, modelHints: hints, urlSession: cancellationSession
            )
        }
        while cancellationCounter.count == 0 { await Task.yield() }
        let waiter = Task {
            try await cancellationResolver.resolve(
                token: "oauth", host: host, modelHints: hints, urlSession: cancellationSession
            )
        }
        await Task.yield()
        waiter.cancel()
        _ = try await owner.value
        await #expect(throws: CancellationError.self) { _ = try await waiter.value }
        #expect(cancellationCounter.count == 1)
    }

    @Test("Auto session cache isolates hosts, accounts, hints, expiry, and invalidation")
    func autoSessionCacheIsolatesKeysAndInvalidation() async throws {
        let individualHost = URL(string: "https://api.individual.githubcopilot.com")!
        let businessHost = URL(string: "https://api.githubcopilot.com")!
        let hintsA = ["model-a"]
        let hintsB = ["model-b"]
        let clock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))

        func makeSession(
            counter: BatchRequestCounter,
            firstExpiry: Int? = nil,
            delayAttempt: Int? = nil
        ) -> URLSession {
            ProviderHTTPMockURLProtocol.makeSession { request in
                _ = counter.record(request: request)
                let attempt = counter.count
                if attempt == delayAttempt {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                let requestBody = String(decoding: request.readMockBody(), as: UTF8.self)
                let model = requestBody.contains("model-b") ? "model-b" : "model-a"
                let expiry = attempt == 1 ? (firstExpiry ?? 4_102_444_800) : 4_102_444_800
                let body = Data("{\"selected_model\":\"\(model)\",\"available_models\":[\"\(model)\"],\"session_token\":\"token-\(attempt)\",\"expires_at\":\(expiry)}".utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
        }

        let hostCounter = BatchRequestCounter()
        let hostSession = makeSession(counter: hostCounter)
        defer { ProviderHTTPMockURLProtocol.releaseSession(hostSession) }
        let hostResolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await hostResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: hostSession)
        _ = try await hostResolver.resolve(token: "account-a", host: businessHost, modelHints: hintsA, urlSession: hostSession)
        #expect(hostCounter.capturedRequests.allSatisfy {
            $0.value(forHTTPHeaderField: "Copilot-Session-Token") == nil
        })

        let accountCounter = BatchRequestCounter()
        let accountSession = makeSession(counter: accountCounter)
        defer { ProviderHTTPMockURLProtocol.releaseSession(accountSession) }
        let accountResolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await accountResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: accountSession)
        _ = try await accountResolver.resolve(token: "account-b", host: individualHost, modelHints: hintsA, urlSession: accountSession)
        _ = try await accountResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: accountSession)
        #expect(accountCounter.count == 3)

        let hintCounter = BatchRequestCounter()
        let hintSession = makeSession(counter: hintCounter)
        defer { ProviderHTTPMockURLProtocol.releaseSession(hintSession) }
        let hintResolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await hintResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: hintSession)
        _ = try await hintResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsB, urlSession: hintSession)
        _ = try await hintResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: hintSession)
        #expect(hintCounter.count == 3)

        let expiryCounter = BatchRequestCounter()
        let expirySession = makeSession(counter: expiryCounter, firstExpiry: 2_000)
        defer { ProviderHTTPMockURLProtocol.releaseSession(expirySession) }
        let expiryResolver = CopilotAutoSessionResolver(now: clock.now)
        _ = try await expiryResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: expirySession)
        clock.advance(by: 1_001)
        _ = try await expiryResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: expirySession)
        let expiryRequests = expiryCounter.capturedRequests
        #expect(expiryRequests.count == 2)
        #expect(expiryRequests.last?.value(forHTTPHeaderField: "Copilot-Session-Token") == nil)

        let invalidationCounter = BatchRequestCounter()
        let invalidationSession = makeSession(counter: invalidationCounter, firstExpiry: 1_200, delayAttempt: 2)
        defer { ProviderHTTPMockURLProtocol.releaseSession(invalidationSession) }
        let invalidationClock = CopilotTestClock(Date(timeIntervalSince1970: 1_000))
        let invalidationResolver = CopilotAutoSessionResolver(now: invalidationClock.now)
        _ = try await invalidationResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: invalidationSession)
        let refresh = Task {
            try await invalidationResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: invalidationSession)
        }
        while invalidationCounter.count < 2 { await Task.yield() }
        await invalidationResolver.invalidate(token: "account-a", host: individualHost, modelHints: hintsA)
        _ = try await refresh.value
        _ = try await invalidationResolver.resolve(token: "account-a", host: individualHost, modelHints: hintsA, urlSession: invalidationSession)
        #expect(invalidationCounter.count == 3)
        #expect(invalidationCounter.capturedRequests.last?.value(forHTTPHeaderField: "Copilot-Session-Token") == nil)
    }

    @Test("Auto translation rejects an empty compatible hint set before session acquisition")
    func autoTranslationRejectsEmptyCompatibleHintsBeforeSessionAcquisition() async {
        let counter = BatchRequestCounter()
        let responsesOnlyJSON = Data("{\"data\":[{\"id\":\"responses-only\",\"name\":\"Responses Only\",\"supported_endpoints\":[\"/responses\"]}]}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responsesOnlyJSON)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )

        await #expect(throws: CopilotCatalogSelectionError.noCompatibleModels) {
            _ = try await service.translate(
                bubbles: [makeSingleBubble()],
                from: .ja,
                to: .en,
                context: .empty,
                token: "oauth-token"
            )
        }
        #expect(counter.capturedRequests.compactMap(\.url?.path) == ["/models", "/models"])
    }

    @Test("Cancellation before Auto acquisition issues no protocol requests")
    func cancellationBeforeAutoAcquisitionIssuesNoProtocolRequests() async {
        let counter = BatchRequestCounter()
        let gate = CopilotAsyncTestGate()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }
        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )
        let task = Task {
            await gate.wait()
            return try await service.translate(
                bubbles: [makeSingleBubble()],
                from: .ja,
                to: .en,
                context: .empty,
                token: "oauth-token"
            )
        }
        while !(await gate.hasWaiter()) { await Task.yield() }
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(counter.count == 0)
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

// MARK: - Multi-page batch tests

/// Thread-safe counter for tracking mock request attempts.
final class BatchRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _capturedBodies: [Data] = []
    private var _capturedRequests: [URLRequest] = []
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    var capturedBodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return _capturedBodies
    }
    var capturedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _capturedRequests
    }
    func record(request: URLRequest) -> Int {
        record(body: request.readMockBody(), request: request)
    }
    func record(body: Data, request: URLRequest? = nil) -> Int {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        _capturedBodies.append(body)
        if let request {
            _capturedRequests.append(request)
        }
        return _count
    }
}

private func makeSingleBubble(index: Int = 0, text: String = "こんにちは") -> BubbleCluster {
    var b = BubbleCluster(
        boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
        text: text,
        observations: []
    )
    b.index = index
    return b
}

private func makeBatchBubble(index: Int, text: String = "src") -> BubbleCluster {
    var b = BubbleCluster(
        boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
        text: text,
        observations: []
    )
    b.index = index
    return b
}

private func makeBatchInputs(_ pageIds: [String]) -> [BatchPageInput] {
    pageIds.map { BatchPageInput(pageId: $0, bubbles: [makeBatchBubble(index: 0, text: "src-\($0)")]) }
}

private func validSinglePageResponseBody(translation: String) -> Data {
    let content = "[{\"index\":0,\"translation\":\"\(translation)\"}]"
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return Data("{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}".utf8)
}

private func validMultiPageResponseBody(translations: [(pageId: String, text: String)]) -> Data {
    let pages = translations
        .map { "{\"page_id\":\"\($0.pageId)\",\"bubbles\":[{\"index\":0,\"translation\":\"\($0.text)\"}]}" }
        .joined(separator: ",")
    let content = "{\"pages\":[\(pages)]}"
    // Escape the content for embedding in the OpenAI-compatible choices.message.content field.
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return Data("{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}".utf8)
}

private func explicitModelCatalogResponse(for request: URLRequest) -> (HTTPURLResponse, Data)? {
    guard request.url?.path == "/models" else { return nil }
    let body = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":true,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
    return (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        body
    )
}

@Suite("CopilotTranslationService translateBatch")
struct CopilotTranslationServiceBatchTests {

    private func makeService(session: URLSession) -> CopilotTranslationService {
        CopilotTranslationService(model: "gpt-5-mini", urlSession: session)
    }

    @Test("Auto batch resolves one compatible session and preserves requested order")
    func autoBatchResolvesOneCompatibleSessionAndPreservesOrder() async throws {
        let counter = BatchRequestCounter()
        let modelsJSON = Data("{\"data\":[{\"id\":\"gpt-5-mini\",\"name\":\"GPT-5 mini\",\"model_picker_enabled\":false,\"supported_endpoints\":[\"/chat/completions\"]}]}".utf8)
        let sessionJSON = Data("{\"selected_model\":\"gpt-5-mini\",\"available_models\":[\"gpt-5-mini\"],\"session_token\":\"batch-session\",\"expires_at\":4102444800}".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(request: request)
            switch request.url?.path {
            case "/models":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, modelsJSON)
            case "/models/session":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, sessionJSON)
            case "/chat/completions":
                let body = validMultiPageResponseBody(translations: [("2", "T2"), ("1", "T1")])
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            default:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = CopilotTranslationService(
            model: "auto",
            urlSession: session,
            catalogStore: CopilotModelCatalogStore(),
            sessionResolver: CopilotAutoSessionResolver()
        )
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1", "2"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "oauth-token"
        )

        #expect(outputs.map(\.pageId) == ["1", "2"])
        #expect(counter.capturedRequests.compactMap(\.url?.path) == [
            "/models", "/models/session", "/chat/completions"
        ])
        #expect(counter.capturedRequests.filter { $0.url?.path == "/models/session" }.count == 1)
    }

    @Test("translate falls back from individual to business endpoint")
    func translateFallsBackToBusinessEndpoint() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            let attempt = counter.record(request: request)
            if request.url?.host == "api.individual.githubcopilot.com" {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (resp, Data("individual unavailable".utf8))
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            #expect(attempt == 3)
            return (resp, validSinglePageResponseBody(translation: "Business OK"))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let output = try await service.translate(
            bubbles: [makeSingleBubble()],
            from: .ja,
            to: .en,
            context: .empty,
            token: "copilot-token-test"
        )

        #expect(output.bubbles.first?.translatedText == "Business OK")
        #expect(counter.capturedRequests.compactMap { $0.url?.host } == [
            "api.individual.githubcopilot.com",
            "api.individual.githubcopilot.com",
            "api.githubcopilot.com"
        ])
        let fallbackRequest = try #require(counter.capturedRequests.last)
        #expect(fallbackRequest.value(forHTTPHeaderField: "Copilot-Integration-Id") == "copilot-developer-cli")
        #expect(fallbackRequest.value(forHTTPHeaderField: "X-GitHub-Api-Version") == nil)
    }

    @Test("translateBatch falls back from individual to business endpoint")
    func translateBatchFallsBackToBusinessEndpoint() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            let attempt = counter.record(request: request)
            if request.url?.host == "api.individual.githubcopilot.com" {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (resp, Data("individual unavailable".utf8))
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            #expect(attempt == 3)
            return (resp, validMultiPageResponseBody(translations: [("1", "T1")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.map { $0.pageId } == ["1"])
        #expect(counter.capturedRequests.compactMap { $0.url?.host } == [
            "api.individual.githubcopilot.com",
            "api.individual.githubcopilot.com",
            "api.githubcopilot.com"
        ])
    }

    @Test("translateBatch sends multi-page request with recent context block")
    func sendsMultiPageRequest() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, validMultiPageResponseBody(translations: [("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let priorContext = TranslationContext(glossaryTerms: [], recentPageSummaries: ["page-A-summary"])
        let inputs = makeBatchInputs(["1", "2"])

        _ = try await service.translateBatch(
            pageInputs: inputs,
            from: .ja,
            to: .en,
            priorContext: priorContext,
            token: "copilot-token-test"
        )

        let body = try #require(counter.capturedBodies.first)
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("page_id"))
        #expect(bodyString.contains("Recent context"))
        #expect(bodyString.contains("page-A-summary"))
    }

    @Test("translateBatch returns outputs in requested order regardless of response order")
    func returnsOutputsInRequestedOrder() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Response intentionally shuffled
            return (resp, validMultiPageResponseBody(translations: [("3", "T3"), ("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1", "2", "3"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.map { $0.pageId } == ["1", "2", "3"])
    }

    @Test("translateBatch retries once on HTTP 500 then succeeds")
    func retriesOnceOnHTTP500() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            let attempt = counter.record(body: request.readMockBody())
            if attempt == 1 {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (resp, Data("internal error".utf8))
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, validMultiPageResponseBody(translations: [("1", "T1")]))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.count == 1)
        #expect(counter.count == 2)
    }

    @Test("translateBatch throws after both endpoints exhaust HTTP 500")
    func throwsAfterBothEndpointsExhaustHTTP500() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("internal error".utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeBatchInputs(["1"]),
                from: .ja,
                to: .en,
                priorContext: .empty,
                token: "copilot-token-test"
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 4)
        let error = try #require(caught)
        // Non-cancellation error = fallback trigger
        #expect(!(error is CancellationError))
        if let urlError = error as? URLError {
            #expect(urlError.code != .cancelled)
        }
    }

    @Test("translateBatch throws on missing page id after retry (fallback trigger)")
    func throwsOnMissingPageId() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Missing page "2"
            return (resp, validMultiPageResponseBody(translations: [("1", "T1"), ("3", "T3")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeBatchInputs(["1", "2", "3"]),
                from: .ja,
                to: .en,
                priorContext: .empty,
                token: "copilot-token-test"
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 4)
        let parseError = try #require(caught as? LLMResponseParser.MultiPageParseError)
        if case .missingPage(let id) = parseError {
            #expect(id == "2")
        } else {
            Issue.record("Expected .missingPage, got \(parseError)")
        }
    }

    @Test("translateBatch accepts any 2xx response status (e.g. 201)")
    func acceptsAny2xxStatus() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            _ = counter.record(body: request.readMockBody())
            // 201 is still a 2xx; the spec accepts the whole 200–299 range.
            let resp = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (resp, validMultiPageResponseBody(translations: [("1", "T1")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.count == 1)
        #expect(counter.count == 1)
    }

    @Test("request body caps max_tokens and uses the shared temperature")
    func setsMaxTokensAndTemperature() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            if let response = explicitModelCatalogResponse(for: request) { return response }
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, validMultiPageResponseBody(translations: [("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        _ = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1", "2"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        let body = try #require(counter.capturedBodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Without max_tokens a runaway repetition loop bills up to the model's
        // full output window; the request must always carry an explicit cap.
        let maxTokens = try #require(json["max_tokens"] as? Int)
        #expect(maxTokens == ChatCompletionsClient.estimatedMaxTokens(bubbleCount: 2, pageCount: 2))
        let temperature = try #require(json["temperature"] as? Double)
        #expect(temperature == ChatCompletionsClient.temperature)
        #expect(temperature == 0.3)
    }

    @Test("estimatedMaxTokens scales with bubbles and keeps per-bubble headroom")
    func estimatedMaxTokensScaling() {
        // The cap exists to bound runaway cost, but it must never truncate a
        // legitimate full-page translation: each extra bubble needs enough
        // headroom for its translated text plus JSON scaffolding, including
        // token-heavy target languages (CJK ~1-2 tokens per character).
        let single = ChatCompletionsClient.estimatedMaxTokens(bubbleCount: 1, pageCount: 1)
        let busyPage = ChatCompletionsClient.estimatedMaxTokens(bubbleCount: 31, pageCount: 1)
        #expect((busyPage - single) / 30 >= 1024)
        // Even an empty page keeps a positive base for JSON scaffolding and
        // the optional detected_terms block.
        #expect(ChatCompletionsClient.estimatedMaxTokens(bubbleCount: 0, pageCount: 1) > 0)
    }

    @Test("translateBatch propagates cancellation without retry or fallback")
    func doesNotRetryOrFallbackOnCancellation() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request -> Result<(HTTPURLResponse, Data), URLError> in
            if let response = explicitModelCatalogResponse(for: request) { return .success(response) }
            _ = counter.record(body: request.readMockBody())
            return .failure(URLError(.cancelled))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeBatchInputs(["1"]),
                from: .ja,
                to: .en,
                priorContext: .empty,
                token: "copilot-token-test"
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 1)
        let urlError = try #require(caught as? URLError)
        #expect(urlError.code == .cancelled)
    }
}
