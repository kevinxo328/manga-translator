import AppKit
import Foundation
import Network

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
        try await request(["grant_type": "authorization_code", "code": code, "client_id": clientID, "redirect_uri": redirectURI.absoluteString, "code_verifier": verifier])
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
            let updated = ChatGPTPlanSession(email: session.email, subject: session.subject, clientID: session.clientID, idToken: token.idToken, accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: now().addingTimeInterval(token.expiresIn), scopes: Set(token.scope.split(separator: " ").map(String.init)))
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
