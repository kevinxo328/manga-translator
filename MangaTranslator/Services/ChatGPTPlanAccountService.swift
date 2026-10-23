import AppKit
import Foundation
import Network

struct ChatGPTPlanModel: Identifiable, Hashable {
    let id: String

    var displayName: String { id }
}

actor ChatGPTPlanModelCatalogStore {
    static let shared = ChatGPTPlanModelCatalogStore()

    private struct Entry {
        let models: [ChatGPTPlanModel]
        let fetchedAt: Date
    }

    private let now: @Sendable () -> Date
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<[ChatGPTPlanModel], Error>] = [:]

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func models(
        accountID: String,
        fetch: @escaping @Sendable () async throws -> [ChatGPTPlanModel]
    ) async throws -> [ChatGPTPlanModel] {
        let currentTime = now()
        entries = entries.filter { currentTime.timeIntervalSince($0.value.fetchedAt) < 300 }
        if let entry = entries[accountID] {
            return entry.models
        }
        if let task = inFlight[accountID] {
            return try await task.value
        }

        let task = Task { try await fetch() }
        inFlight[accountID] = task
        do {
            let models = try await task.value
            inFlight[accountID] = nil
            entries[accountID] = Entry(models: models, fetchedAt: now())
            return models
        } catch {
            inFlight[accountID] = nil
            throw error
        }
    }
}

struct ChatGPTPlanModelCatalogService {
    static let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!

    static func fetchModels(accessToken: String, session: URLSession = .shared) async throws -> [ChatGPTPlanModel] {
        var request = URLRequest(url: modelsEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ 200 ..< 300 ~= $0.statusCode }) == true else {
            throw TranslationError.invalidResponse
        }
        return try parseModels(data)
    }

    static func parseModels(_ data: Data) throws -> [ChatGPTPlanModel] {
        struct Response: Decodable {
            struct Model: Decodable {
                let id: String
                let object: String?
            }

            let data: [Model]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let uniqueIDs = Set(response.data.compactMap { model -> String? in
            guard model.object == "model", !model.id.isEmpty else { return nil }
            return model.id
        })
        return uniqueIDs.sorted().map(ChatGPTPlanModel.init(id:))
    }
}

enum ChatGPTPlanModelLoadState: Equatable {
    case idle
    case loading
    case selectable([ChatGPTPlanModel])
    case noModels
    case failed(String)

    static func loaded(_ models: [ChatGPTPlanModel]) -> ChatGPTPlanModelLoadState {
        models.isEmpty ? .noModels : .selectable(models)
    }

    static func failed(from error: Error) -> ChatGPTPlanModelLoadState {
        _ = error
        return .failed("Couldn’t load ChatGPT models.")
    }
}

enum ChatGPTPlanModelControls: Equatable {
    case none
    case loading
    case picker([ChatGPTPlanModel])
    case noModels
    case retry

    static func forState(_ state: ChatGPTPlanModelLoadState) -> ChatGPTPlanModelControls {
        switch state {
        case .idle: .none
        case .loading: .loading
        case .selectable(let models): .picker(models)
        case .noModels: .noModels
        case .failed: .retry
        }
    }
}

enum ChatGPTPlanModelSelection {
    static func defaulting(_ savedModelID: String?, from models: [ChatGPTPlanModel]) -> String? {
        savedModelID ?? models.first?.id
    }
}

@MainActor
final class ChatGPTPlanModelSettingsState {
    private let fetch: () async throws -> [ChatGPTPlanModel]
    private let save: (String?) async throws -> Void
    private(set) var loadState: ChatGPTPlanModelLoadState = .idle
    private(set) var selectedModel: String?

    init(
        selectedModel: String?,
        fetch: @escaping () async throws -> [ChatGPTPlanModel],
        save: @escaping (String?) async throws -> Void
    ) {
        self.selectedModel = selectedModel
        self.fetch = fetch
        self.save = save
    }

    func load() async {
        loadState = .loading
        do {
            let models = try await fetch()
            let selection = ChatGPTPlanModelSelection.defaulting(selectedModel, from: models)
            if selection != selectedModel {
                try await save(selection)
                selectedModel = selection
            }
            loadState = .loaded(models)
        } catch {
            loadState = .failed(from: error)
        }
    }
}

protocol ChatGPTPlanOAuthTransport: Sendable {
    func exchange(code: String, clientID: String, redirectURI: URL, verifier: String) async throws -> ChatGPTPlanTokenResponse
    func refresh(refreshToken: String, clientID: String) async throws -> ChatGPTPlanTokenResponse
    func revoke(refreshToken: String, clientID: String) async throws
}

struct ChatGPTPlanTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String
    let expiresIn: TimeInterval
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token", expiresIn = "expires_in", scope
    }
}

struct ChatGPTPlanHTTPTransport: ChatGPTPlanOAuthTransport {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func exchange(code: String, clientID: String, redirectURI: URL, verifier: String) async throws -> ChatGPTPlanTokenResponse {
        try await request([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI.absoluteString,
            "code_verifier": verifier,
            "resource": ChatGPTPlanOAuth.resource
        ])
    }

    func refresh(refreshToken: String, clientID: String) async throws -> ChatGPTPlanTokenResponse {
        try await request(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }

    func revoke(refreshToken: String, clientID: String) async throws {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["token": refreshToken, "client_id": clientID])
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ 200 ..< 300 ~= $0.statusCode }) == true else { throw ChatGPTPlanOAuthError.invalidCallback }
    }

    private func request(_ values: [String: String]) async throws -> ChatGPTPlanTokenResponse {
        var request = URLRequest(url: ChatGPTPlanOAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(values)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ 200 ..< 300 ~= $0.statusCode }) == true else { throw ChatGPTPlanOAuthError.invalidCallback }
        return try JSONDecoder().decode(ChatGPTPlanTokenResponse.self, from: data)
    }

    private func form(_ values: [String: String]) -> Data? {
        values.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(key)=\(encoded)"
        }.joined(separator: "&").data(using: .utf8)
    }
}

/// Owns one browser callback. It listens only on localhost and is started before opening the browser.
@MainActor
final class ChatGPTPlanLoopbackListener {
    private var listener: NWListener?
    private var callback: CheckedContinuation<URL, Error>?
    private var receivedCallback: Result<URL, Error>?

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.receive(connection) }
                }
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        switch state {
                        case .ready:
                            guard let port = self?.listener?.port else { return }
                            continuation.resume(returning: URL(string: "http://127.0.0.1:\(port)/callback")!)
                        case .failed(let error): continuation.resume(throwing: error)
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
            } catch { continuation.resume(throwing: error) }
        }
    }

    func waitForCallback() async throws -> URL {
        if let receivedCallback { return try receivedCallback.get() }
        return try await withCheckedThrowingContinuation { callback = $0 }
    }

    func cancel() { listener?.cancel(); listener = nil }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, error in
            defer { connection.cancel(); Task { @MainActor in self?.cancel() } }
            guard error == nil, let data, let request = String(data: data, encoding: .utf8), let target = request.split(separator: "\n").first?.split(separator: " ").dropFirst().first, let url = URL(string: "http://127.0.0.1\(target)") else {
                Task { @MainActor in self?.finish(.failure(ChatGPTPlanOAuthError.invalidCallback)) }; return
            }
            connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 45\r\n\r\nYou may return to MangaTranslator.".utf8), completion: .contentProcessed { _ in })
            Task { @MainActor in self?.finish(.success(url)) }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let callback else { receivedCallback = result; return }
        self.callback = nil
        callback.resume(with: result)
    }
}

actor ChatGPTPlanAccountService {
    private let transport: any ChatGPTPlanOAuthTransport
    private let load: @Sendable () -> ChatGPTPlanSession?
    private let save: @Sendable (ChatGPTPlanSession) -> Void
    private let clear: @Sendable () -> Void
    private let now: @Sendable () -> Date
    private let hostID: String
    private var refreshTask: Task<ChatGPTPlanSession, Error>?

    init(transport: any ChatGPTPlanOAuthTransport = ChatGPTPlanHTTPTransport(), store: ChatGPTPlanSessionStore = ChatGPTPlanSessionStore(), now: @escaping @Sendable () -> Date = Date.init, hostID: String = ChatGPTPlanAccountService.installationHostID()) {
        self.transport = transport
        self.load = { store.load() }
        self.save = { store.save($0) }
        self.clear = { store.clear() }
        self.now = now
        self.hostID = hostID
    }

    init(transport: any ChatGPTPlanOAuthTransport, load: @escaping @Sendable () -> ChatGPTPlanSession?, save: @escaping @Sendable (ChatGPTPlanSession) -> Void, clear: @escaping @Sendable () -> Void, now: @escaping @Sendable () -> Date = Date.init, hostID: String = "test-host") {
        self.transport = transport; self.load = load; self.save = save; self.clear = clear; self.now = now; self.hostID = hostID
    }

    func session() -> ChatGPTPlanSession? { load() }

    func selectModel(_ modelID: String?) throws -> ChatGPTPlanSession {
        guard let session = load() else { throw TranslationError.missingAPIKey(.chatGPTPlan) }
        let updated = ChatGPTPlanSession(
            email: session.email,
            subject: session.subject,
            clientID: session.clientID,
            idToken: session.idToken,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt,
            scopes: session.scopes,
            selectedModel: modelID
        )
        save(updated)
        return updated
    }

    func signIn() async throws -> ChatGPTPlanSession {
        let listener = await MainActor.run { ChatGPTPlanLoopbackListener() }
        let redirectURI = try await listener.start()
        let attempt = ChatGPTPlanAuthorizationAttempt.make(redirectURI: redirectURI, issuedClientID: load()?.clientID)
        let authorizationURL = ChatGPTPlanOAuth.authorizationURL(for: attempt, hostID: hostID)
        await MainActor.run { NSWorkspace.shared.open(authorizationURL) }
        let callbackURL = try await listener.waitForCallback()
        let callback = try ChatGPTPlanOAuth.validate(callbackURL: callbackURL, for: attempt)
        let clientID = callback.clientID ?? attempt.clientID
        let token = try await transport.exchange(code: callback.code, clientID: clientID, redirectURI: redirectURI, verifier: attempt.verifier)
        let identity = try ChatGPTPlanOAuth.identity(from: token.idToken, expectedNonce: attempt.nonce, clientID: clientID, now: now())
        let session = makeSession(token, identity: identity, clientID: clientID)
        guard session.isAuthorizedForPlanUsage else { throw ChatGPTPlanOAuthError.missingPlanScope }
        save(session)
        return session
    }

    func validAccessToken() async throws -> String {
        guard let session = load() else { throw TranslationError.missingAPIKey(.chatGPTPlan) }
        if session.expiresAt > now().addingTimeInterval(60) { return session.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { [transport, now, save] () throws -> ChatGPTPlanSession in
            let token = try await transport.refresh(refreshToken: session.refreshToken, clientID: session.clientID)
            let updated = ChatGPTPlanSession(email: session.email, subject: session.subject, clientID: session.clientID, idToken: token.idToken, accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: now().addingTimeInterval(token.expiresIn), scopes: Set(token.scope.split(separator: " ").map(String.init)), selectedModel: session.selectedModel)
            guard updated.isAuthorizedForPlanUsage else { throw ChatGPTPlanOAuthError.missingPlanScope }
            save(updated); return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    func signOut() async throws {
        guard let session = load() else { return }
        defer { clear() }
        try await transport.revoke(refreshToken: session.refreshToken, clientID: session.clientID)
    }

    private func makeSession(_ token: ChatGPTPlanTokenResponse, identity: (email: String, subject: String), clientID: String) -> ChatGPTPlanSession {
        ChatGPTPlanSession(email: identity.email, subject: identity.subject, clientID: clientID, idToken: token.idToken, accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: now().addingTimeInterval(token.expiresIn), scopes: Set(token.scope.split(separator: " ").map(String.init)))
    }

    private static func installationHostID() -> String {
        let key = "chatGPTPlanInstallationHostID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
