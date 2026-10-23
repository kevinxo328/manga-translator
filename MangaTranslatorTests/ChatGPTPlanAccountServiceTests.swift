import Foundation
import Testing
@testable import MangaTranslator

@Suite("ChatGPTPlanAccountService")
struct ChatGPTPlanAccountServiceTests {
    @Test("Sign-in persists the verified account after the browser callback")
    @MainActor
    func signInCompletesThroughInjectedBrowserAndCallback() async throws {
        let browser = BrowserStub()
        let listener = CallbackListenerStub { browser.authorizationURL }
        let store = SessionBox(session: nil)
        let transport = OAuthTransportStub(exchange: { await browser.tokenResponse() })
        let service = ChatGPTPlanAccountService(
            transport: transport,
            idTokenVerifier: IDTokenVerifierStub(),
            load: { store.session }, save: { store.session = $0 }, clear: { store.session = nil },
            now: { Date(timeIntervalSince1970: 1_000) },
            listenerFactory: { listener },
            openBrowser: { url in browser.authorizationURL = url; return true }
        )
        listener.callbackURL = { [weak browser] in
            let items = URLComponents(url: browser?.authorizationURL ?? URL(string: "https://invalid.example")!, resolvingAgainstBaseURL: false)?.queryItems
            let state = items?.first(where: { $0.name == "state" })?.value ?? ""
            return URL(string: "http://127.0.0.1:1234/callback?code=code&state=\(state)&client_id=issued-client")!
        }

        let session = try await service.signIn()

        #expect(browser.authorizationURL != nil)
        #expect(session.email == "reader@example.com")
        #expect(store.session == session)
    }
    @Test("ID token verifier rejects unsigned tokens before accepting account claims")
    func idTokenVerifierRejectsUnsignedToken() async {
        let unsignedToken = "eyJhbGciOiJub25lIiwia2lkIjoia2lkIn0.eyJzdWIiOiJ1c2VyIn0."

        await #expect(throws: ChatGPTPlanOAuthError.invalidIDTokenSignature) {
            try await ChatGPTPlanIDTokenVerifier().verifySignature(of: unsignedToken)
        }
    }

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

    @Test("OAuth listener accepts the browser callback and returns its parameters")
    @MainActor
    func loopbackListenerReceivesCallback() async throws {
        let listener = ChatGPTPlanLoopbackListener()
        defer { listener.cancel() }
        let redirectURI = try await listener.start()
        let callback = Task { try await listener.waitForCallback() }
        let requestURL = URL(string: "\(redirectURI.absoluteString)?code=authorization-code&state=state")!

        let (_, response) = try await URLSession.shared.data(from: requestURL)
        let returnedURL = try await callback.value

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(URLComponents(url: returnedURL, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "code", value: "authorization-code")) == true)
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

    @Test("Plan translation requires a selected account model")
    func planTranslationReportsMissingModel() async {
        let service = ChatGPTPlanTranslationService(account: account(with: session()))

        do {
            _ = try await service.translate(bubbles: [], from: .ja, to: .en, context: .empty)
            Issue.record("Expected a missing-model error")
        } catch TranslationError.chatGPTPlanModelNotSelected {
            // Expected: a session alone is not enough to create a Responses request.
        } catch {
            Issue.record("Expected chatGPTPlanModelNotSelected, got \(error)")
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
        #expect(form.contains("resource=https%3A%2F%2Fapi.openai.com%2Fv1"))
    }

    @Test("Refresh and revoke requests preserve the direct-plan OAuth grant")
    func refreshAndRevokeIncludeRequiredOAuthFields() async throws {
        let captured = RequestListBox()
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"access_token":"access","refresh_token":"refresh","id_token":"id","expires_in":3600,"scope":"openid"}"#.utf8)
            return (response, data)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }

        let transport = ChatGPTPlanHTTPTransport(session: httpSession)
        _ = try await transport.refresh(refreshToken: "refresh+/=", clientID: "client-id")
        try await transport.revoke(refreshToken: "refresh+/=", clientID: "client-id")

        let requests = captured.requests
        #expect(requests.count == 2)
        let refreshForm = String(data: requests[0].readMockBody(), encoding: .utf8) ?? ""
        let revokeForm = String(data: requests[1].readMockBody(), encoding: .utf8) ?? ""
        #expect(refreshForm.contains("resource=https%3A%2F%2Fapi.openai.com%2Fv1"))
        #expect(refreshForm.contains("refresh_token=refresh%2B%2F%3D"))
        #expect(revokeForm.contains("token_type_hint=refresh_token"))
        #expect(revokeForm.contains("token=refresh%2B%2F%3D"))
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
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "user")
        #expect((input[0]["content"] as? String)?.contains("こんにちは") == true)
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

    @Test("Plan batch requests strict structured output and validates its page contract")
    func planBatchRequestsStrictStructuredOutput() async throws {
        let captured = RequestBox()
        let sse = completedBatchSSE(#"{"pages":[{"page_id":"1","bubbles":[{"index":0,"translation":"Hello"}],"detected_terms":[]}]}"#)
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.request = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(sse.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }

        let service = ChatGPTPlanTranslationService(
            account: account(with: session(selectedModel: "gpt-5")),
            urlSession: httpSession,
            defaults: isolatedDefaults()
        )

        let output = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)

        #expect(output.first?.bubbles.first?.translatedText == "Hello")
        let format = try #require(captured.request?.jsonMockBody()["text"] as? [String: Any])
        let schemaFormat = try #require(format["format"] as? [String: Any])
        #expect(schemaFormat["type"] as? String == "json_schema")
        #expect(schemaFormat["strict"] as? Bool == true)
        let schema = try #require(schemaFormat["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test("Plan batch retries a structured-output rejection with prompt-only JSON for seven days")
    func planBatchFallsBackAfterStructuredOutputRejection() async throws {
        let captured = RequestListBox()
        let defaults = isolatedDefaults()
        var calls = 0
        let success = completedBatchSSE(#"{"pages":[{"page_id":"1","bubbles":[{"index":0,"translation":"Hello"}],"detected_terms":[]}]}"#)
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.requests.append(request)
            calls += 1
            if calls == 1 {
                let body = #"{"error":{"code":"unsupported_parameter","message":"Structured Outputs are not supported for this model"}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(success.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }
        let service = ChatGPTPlanTranslationService(
            account: account(with: session(selectedModel: "gpt-5")), urlSession: httpSession, defaults: defaults
        )

        _ = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)
        _ = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)

        #expect(captured.requests.count == 3)
        #expect(captured.requests[0].jsonMockBody()["text"] != nil)
        #expect(captured.requests[1].jsonMockBody()["text"] == nil)
        #expect(captured.requests[2].jsonMockBody()["text"] == nil)
    }

    @Test("Plan batch retries strict output after its unsupported capability expires")
    func planBatchRetriesStructuredOutputAfterCapabilityExpiry() async throws {
        let captured = RequestListBox()
        let defaults = isolatedDefaults()
        let clock = ChatGPTPlanCatalogTestClock(Date(timeIntervalSince1970: 1_000))
        var calls = 0
        let success = completedBatchSSE(#"{"pages":[{"page_id":"1","bubbles":[{"index":0,"translation":"Hello"}],"detected_terms":[]}]}"#)
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.requests.append(request)
            calls += 1
            if calls == 1 {
                let body = #"{"error":{"code":"unsupported_parameter","message":"Structured Outputs are not supported"}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(success.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }
        let service = ChatGPTPlanTranslationService(
            account: account(with: session(selectedModel: "gpt-5")), urlSession: httpSession, defaults: defaults, now: { clock.now() }
        )

        _ = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)
        clock.advance(by: 7 * 24 * 60 * 60 + 1)
        _ = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)

        #expect(captured.requests.count == 3)
        #expect(captured.requests[2].jsonMockBody()["text"] != nil)
    }

    @Test("Plan batch does not cache a temporary provider refusal as unsupported output")
    func planBatchDoesNotCacheTemporaryProviderRefusal() async throws {
        let captured = RequestListBox()
        var calls = 0
        let success = completedBatchSSE(#"{"pages":[{"page_id":"1","bubbles":[{"index":0,"translation":"Hello"}],"detected_terms":[]}]}"#)
        let httpSession = ProviderHTTPMockURLProtocol.makeSession { request in
            captured.requests.append(request)
            calls += 1
            if calls == 1 {
                let body = #"{"error":{"code":"rate_limit_exceeded","message":"Structured output requests are temporarily unavailable"}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(success.utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(httpSession) }
        let service = ChatGPTPlanTranslationService(
            account: account(with: session(selectedModel: "gpt-5")), urlSession: httpSession, defaults: isolatedDefaults()
        )

        await #expect(throws: TranslationError.self) {
            _ = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)
        }
        _ = try await service.translateBatch(pageInputs: [batchPage()], from: .ja, to: .en, priorContext: .empty)

        #expect(captured.requests.count == 2)
        #expect(captured.requests.allSatisfy { $0.jsonMockBody()["text"] != nil })
    }
    @Test("catalog keeps displayable plan models in server order")
    func catalogFiltersDisplayableModels() throws {
        let data = """
        {
          "models": [
            { "slug": "gpt-5", "display_name": "GPT 5", "visibility": "list" },
            { "slug": "hidden", "display_name": "Hidden", "visibility": "hidden" },
            { "slug": "gpt-5", "display_name": "Duplicate", "visibility": "list" },
            { "slug": "gpt-5-mini", "display_name": "GPT 5 Mini", "visibility": "list" }
          ]
        }
        """.data(using: .utf8)!

        let models = try ChatGPTPlanModelCatalogService.parseModels(data)
        #expect(models.map(\.id) == ["gpt-5", "gpt-5-mini"])
        #expect(models.map(\.displayName) == ["GPT 5", "GPT 5 Mini"])
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

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ChatGPTPlanTranslationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func batchPage() -> BatchPageInput {
        var bubble = BubbleCluster(boundingBox: .zero, text: "こんにちは", observations: [])
        bubble.index = 0
        return BatchPageInput(pageId: "1", bubbles: [bubble])
    }

    private func completedBatchSSE(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "data: {\"type\":\"response.output_text.delta\",\"delta\":\"\(escaped)\"}\n\ndata: {\"type\":\"response.completed\"}\n"
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

private final class RequestListBox: @unchecked Sendable {
    var requests: [URLRequest] = []
}

@MainActor
private final class BrowserStub {
    var authorizationURL: URL?

    func tokenResponse() -> ChatGPTPlanTokenResponse {
        let nonce = URLComponents(url: authorizationURL!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "nonce" })?.value ?? ""
        let claims: [String: Any] = [
            "iss": "https://auth.openai.com", "aud": "issued-client", "nonce": nonce,
            "email_verified": true, "exp": 2_000.0, "email": "reader@example.com", "sub": "reader"
        ]
        let header = Data(#"{"alg":"RS256","kid":"test"}"#.utf8).base64EncodedString()
        let payload = try! JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        return ChatGPTPlanTokenResponse(accessToken: "access", refreshToken: "refresh", idToken: "\(header).\(payload).signature", expiresIn: 3_600, scope: "openid chatgpt.tokens.use.direct")
    }
}

@MainActor
private final class CallbackListenerStub: ChatGPTPlanCallbackListening {
    var callbackURL: (() -> URL)!

    init(_ authorizationURL: @escaping () -> URL?) {}

    func start() async throws -> URL { URL(string: "http://127.0.0.1:1234/callback")! }
    func waitForCallback() async throws -> URL { callbackURL() }
    func cancel() {}
}

private struct IDTokenVerifierStub: ChatGPTPlanIDTokenVerifying {
    func verifySignature(of idToken: String) async throws {}
}

private actor OAuthTransportStub: ChatGPTPlanOAuthTransport {
    let refreshResult: ChatGPTPlanTokenResponse
    let revokeError: Error?
    let exchangeResult: (@Sendable () async -> ChatGPTPlanTokenResponse)?
    var refreshCalls = 0

    init(refreshResult: ChatGPTPlanTokenResponse = ChatGPTPlanTokenResponse(accessToken: "access", refreshToken: "refresh", idToken: "id", expiresIn: 3_600, scope: "openid"), revokeError: Error? = nil, exchange: (@Sendable () async -> ChatGPTPlanTokenResponse)? = nil) {
        self.refreshResult = refreshResult
        self.revokeError = revokeError
        self.exchangeResult = exchange
    }

    func exchange(code: String, clientID: String, redirectURI: URL, verifier: String) async throws -> ChatGPTPlanTokenResponse { await exchangeResult?() ?? refreshResult }
    func refresh(refreshToken: String, clientID: String) async throws -> ChatGPTPlanTokenResponse { refreshCalls += 1; return refreshResult }
    func revoke(refreshToken: String, clientID: String) async throws { if let revokeError { throw revokeError } }
}
