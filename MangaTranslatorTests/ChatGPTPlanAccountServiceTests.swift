import Foundation
import Testing
@testable import MangaTranslator

@Suite("ChatGPTPlanAccountService")
struct ChatGPTPlanAccountServiceTests {
    @Test("OAuth listener starts a loopback callback server")
    @MainActor
    func loopbackListenerStarts() async throws {
        let listener = ChatGPTPlanLoopbackListener()
        defer { listener.cancel() }

        let redirectURI = try await listener.start()

        #expect(redirectURI.scheme == "http")
        #expect(redirectURI.host == "127.0.0.1")
        #expect(redirectURI.path == "/callback")
        #expect(redirectURI.port != nil)
    }

    @Test("OAuth listener cancellation releases a pending sign-in")
    @MainActor
    func loopbackListenerWaitCancels() async throws {
        let listener = ChatGPTPlanLoopbackListener()
        defer { listener.cancel() }
        _ = try await listener.start()
        let callback = Task { try await listener.waitForCallback() }

        callback.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await callback.value
        }
    }

    @Test("Plan translation reports a disconnected account before checking a model")
    func planTranslationReportsDisconnectedAccount() async {
        let service = ChatGPTPlanTranslationService(
            account: ChatGPTPlanAccountService(
                transport: OAuthTransportStub(), load: { nil }, save: { _ in }, clear: {}
            )
        )

        do {
            _ = try await service.translate(bubbles: [], from: .ja, to: .en, context: .empty)
            Issue.record("Expected a disconnected-account error")
        } catch TranslationError.chatGPTPlanNotConnected {
            // Expected: absence of an account is distinct from malformed output.
        } catch {
            Issue.record("Expected chatGPTPlanNotConnected, got \(error)")
        }
    }

    @Test("Token exchange requests access for the Responses API resource")
    func tokenExchangeIncludesResponsesAPIResource() async throws {
        let captured = RequestBox()
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.request = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"access_token":"access","refresh_token":"refresh","id_token":"id","expires_in":3600,"scope":"openid"}"#.utf8)
            return (response, data)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }

        let transport = ChatGPTPlanHTTPTransport(session: httpSession)
        _ = try await transport.exchange(
            code: "authorization-code",
            clientID: "client-id",
            redirectURI: URL(string: "http://127.0.0.1:8080/callback")!,
            verifier: "verifier"
        )

        let request = try #require(captured.request)
        let form = String(data: request.readMockBody(), encoding: .utf8) ?? ""
        #expect(form.contains("resource=\(ChatGPTPlanOAuth.resource)"))
    }

    @Test("Plan translation streams a complete response with the selected model and full context")
    func planTranslationStreamsCompletedResponse() async throws {
        let store = SessionBox(session: session(selectedModel: "gpt-5"))
        let account = ChatGPTPlanAccountService(
            transport: OAuthTransportStub(),
            load: { store.session }, save: { store.session = $0 }, clear: { store.session = nil }
        )
        let captured = RequestBox()
        let sse = """
        data: {"type":"response.output_text.delta","delta":"[{\\\"index\\\":0,"}

        data: {"type":"response.output_text.delta","delta":"\\\"translation\\\":\\\"Hello\\\"}]"}

        data: {"type":"response.completed"}

        """
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.request = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            return (response, Data(sse.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }

        let service = ChatGPTPlanTranslationService(account: account, urlSession: httpSession)
        let context = TranslationContext(
            glossaryTerms: [GlossaryTerm(id: "hero", sourceTerm: "勇者", targetTerm: "Hero", autoDetected: false)],
            recentPageSummaries: ["The hero enters the castle."]
        )
        var bubble = BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [])
        bubble.index = 0

        let output = try await service.translate(bubbles: [bubble], from: .ja, to: .en, context: context)

        #expect(output.bubbles.map(\.translatedText) == ["Hello"])
        let request = try #require(captured.request)
        #expect(request.url == URL(string: "https://api.openai.com/v1/responses"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let body = request.jsonMockBody()
        #expect(body["model"] as? String == "gpt-5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["store"] as? Bool == false)
        #expect((body["instructions"] as? String)?.contains("Glossary") == true)
        #expect((body["instructions"] as? String)?.contains("Recent context") == true)
        #expect(body["temperature"] == nil)
        #expect(body["max_output_tokens"] == nil)
    }

    @Test("Plan translation rejects a stream without a successful terminal event")
    func planTranslationRejectsUnterminatedStream() async {
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"[]\"}\n\n".utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }
        let service = ChatGPTPlanTranslationService(
            account: account(with: session(selectedModel: "gpt-5")),
            urlSession: httpSession
        )

        await #expect(throws: TranslationError.self) {
            _ = try await service.translate(bubbles: [], from: .ja, to: .en, context: .empty)
        }
    }

    @Test("Plan translation surfaces unavailable-model provider errors")
    func planTranslationSurfacesProviderErrors() async {
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"Model unavailable","code":"model_not_found"}}"#.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }
        let service = ChatGPTPlanTranslationService(account: account(with: session(selectedModel: "retired")), urlSession: httpSession)

        do {
            _ = try await service.translate(bubbles: [], from: .ja, to: .en, context: .empty)
            Issue.record("Expected provider error")
        } catch let TranslationError.apiError(error) {
            #expect(error.statusCode == 404)
            #expect(error.code == "model_not_found")
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }
    @Test("catalog keeps only displayable models in a stable order")
    func catalogFiltersDisplayableModels() throws {
        let data = """
        {
          "data": [
            { "id": "gpt-5", "object": "model" },
            { "id": "", "object": "model" },
            { "id": "gpt-5", "object": "model" },
            { "id": "not-a-model", "object": "other" },
            { "id": "chatgpt-5", "object": "model" }
          ]
        }
        """.data(using: .utf8)!

        #expect(try ChatGPTPlanModelCatalogService.parseModels(data).map(\.id) == ["chatgpt-5", "gpt-5"])
    }

    @Test("catalog cache reuses an account catalog for five minutes")
    func catalogCacheExpiresAfterFiveMinutes() async throws {
        let clock = ChatGPTPlanCatalogTestClock(Date(timeIntervalSince1970: 1_000))
        let store = ChatGPTPlanModelCatalogStore(now: clock.now)
        let calls = ChatGPTPlanCatalogCallCounter()

        let first = try await store.models(accountID: "reader") {
            await calls.increment()
            return [ChatGPTPlanModel(id: "gpt-5")]
        }
        clock.advance(by: 299)
        let cached = try await store.models(accountID: "reader") {
            await calls.increment()
            return [ChatGPTPlanModel(id: "different")]
        }
        clock.advance(by: 1)
        let refreshed = try await store.models(accountID: "reader") {
            await calls.increment()
            return [ChatGPTPlanModel(id: "gpt-5.1")]
        }

        #expect(first.map(\.id) == ["gpt-5"])
        #expect(cached.map(\.id) == ["gpt-5"])
        #expect(refreshed.map(\.id) == ["gpt-5.1"])
        #expect(await calls.value == 2)
    }

    @Test("catalog state exposes retry after a loading failure")
    func catalogFailureExposesRetry() {
        let state = ChatGPTPlanModelLoadState.failed(from: URLError(.timedOut))

        #expect(state == .failed("Couldn’t load ChatGPT models."))
        #expect(ChatGPTPlanModelControls.forState(state) == .retry)
    }

    @Test("failed catalog fetch is not cached so retry fetches again")
    func failedCatalogFetchCanRetry() async throws {
        let store = ChatGPTPlanModelCatalogStore()
        let calls = ChatGPTPlanCatalogCallCounter()

        await #expect(throws: URLError(.timedOut)) {
            try await store.models(accountID: "reader") {
                await calls.increment()
                throw URLError(.timedOut)
            }
        }
        let models = try await store.models(accountID: "reader") {
            await calls.increment()
            return [ChatGPTPlanModel(id: "gpt-5")]
        }

        #expect(models.map(\.id) == ["gpt-5"])
        #expect(await calls.value == 2)
    }

    @Test("catalog defaults only an unset selection and never replaces a saved model")
    func catalogPreservesUnavailableSavedSelection() {
        let models = [ChatGPTPlanModel(id: "gpt-5")]

        #expect(ChatGPTPlanModelSelection.defaulting(nil, from: models) == "gpt-5")
        #expect(ChatGPTPlanModelSelection.defaulting("retired-model", from: models) == "retired-model")
    }

    @Test("model selection persists with the linked account")
    func selectedModelPersistsWithLinkedAccount() async throws {
        let store = SessionBox(session: session())
        let service = ChatGPTPlanAccountService(
            transport: OAuthTransportStub(),
            load: { store.session },
            save: { store.session = $0 },
            clear: { store.session = nil }
        )

        let updated = try await service.selectModel("gpt-5")

        #expect(updated.selectedModel == "gpt-5")
        #expect(store.session?.selectedModel == "gpt-5")
    }

    @Test("settings loading defaults and saves only an unset selection")
    @MainActor
    func settingsLoadingDefaultsAndSavesSelection() async {
        var saved: [String?] = []
        let state = ChatGPTPlanModelSettingsState(
            selectedModel: nil,
            fetch: { [ChatGPTPlanModel(id: "gpt-5")] },
            save: { saved.append($0) }
        )

        await state.load()

        #expect(state.loadState == .selectable([ChatGPTPlanModel(id: "gpt-5")]))
        #expect(state.selectedModel == "gpt-5")
        #expect(saved == ["gpt-5"])
    }

    @Test("Expired credentials refresh once and atomically replace rotated tokens")
    func refreshesRotatingCredentials() async throws {
        let store = SessionBox(session: session(expiresAt: .distantPast))
        let transport = OAuthTransportStub(refreshResult: token(access: "new-access", refresh: "new-refresh"))
        let service = ChatGPTPlanAccountService(transport: transport, load: { store.session }, save: { store.session = $0 }, clear: { store.session = nil }, now: { Date(timeIntervalSince1970: 1_000) })

        let access = try await service.validAccessToken()

        #expect(access == "new-access")
        #expect(store.session?.refreshToken == "new-refresh")
        #expect(await transport.refreshCalls == 1)
    }

    @Test("Logout removes local credentials even if remote revocation fails")
    func logoutClearsCredentialsAfterRevocationFailure() async {
        let store = SessionBox(session: session())
        let transport = OAuthTransportStub(revokeError: ChatGPTPlanOAuthError.invalidCallback)
        let service = ChatGPTPlanAccountService(transport: transport, load: { store.session }, save: { store.session = $0 }, clear: { store.session = nil })

        await #expect(throws: ChatGPTPlanOAuthError.invalidCallback) {
            try await service.signOut()
        }

        #expect(store.session == nil)
    }

    private func session(expiresAt: Date = .distantFuture, selectedModel: String? = nil) -> ChatGPTPlanSession {
        ChatGPTPlanSession(email: "reader@example.com", subject: "reader", clientID: "issued-client", idToken: "id", accessToken: "old-access", refreshToken: "old-refresh", expiresAt: expiresAt, scopes: ["chatgpt.tokens.use.direct"], selectedModel: selectedModel)
    }

    private func account(with session: ChatGPTPlanSession) -> ChatGPTPlanAccountService {
        let store = SessionBox(session: session)
        return ChatGPTPlanAccountService(
            transport: OAuthTransportStub(),
            load: { store.session }, save: { store.session = $0 }, clear: { store.session = nil }
        )
    }

    private func token(access: String, refresh: String) -> ChatGPTPlanTokenResponse {
        ChatGPTPlanTokenResponse(accessToken: access, refreshToken: refresh, idToken: "id", expiresIn: 3_600, scope: "openid chatgpt.tokens.use.direct")
    }
}

private final class ChatGPTPlanCatalogTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value.addTimeInterval(interval)
        lock.unlock()
    }
}

private actor ChatGPTPlanCatalogCallCounter {
    private(set) var value = 0

    func increment() { value += 1 }
}

private final class SessionBox: @unchecked Sendable {
    var session: ChatGPTPlanSession?
    init(session: ChatGPTPlanSession?) { self.session = session }
}

private final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
}

private actor OAuthTransportStub: ChatGPTPlanOAuthTransport {
    let refreshResult: ChatGPTPlanTokenResponse
    let revokeError: Error?
    var refreshCalls = 0

    init(refreshResult: ChatGPTPlanTokenResponse = ChatGPTPlanTokenResponse(accessToken: "access", refreshToken: "refresh", idToken: "id", expiresIn: 3_600, scope: "openid"), revokeError: Error? = nil) {
        self.refreshResult = refreshResult
        self.revokeError = revokeError
    }

    func exchange(code: String, clientID: String, redirectURI: URL, verifier: String) async throws -> ChatGPTPlanTokenResponse { refreshResult }
    func refresh(refreshToken: String, clientID: String) async throws -> ChatGPTPlanTokenResponse { refreshCalls += 1; return refreshResult }
    func revoke(refreshToken: String, clientID: String) async throws { if let revokeError { throw revokeError } }
}
