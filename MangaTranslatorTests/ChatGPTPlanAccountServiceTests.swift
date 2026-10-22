import Foundation
import Testing
@testable import MangaTranslator

@Suite("ChatGPTPlanAccountService")
struct ChatGPTPlanAccountServiceTests {
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

    private func session(expiresAt: Date = .distantFuture) -> ChatGPTPlanSession {
        ChatGPTPlanSession(email: "reader@example.com", subject: "reader", clientID: "issued-client", idToken: "id", accessToken: "old-access", refreshToken: "old-refresh", expiresAt: expiresAt, scopes: ["chatgpt.tokens.use.direct"])
    }

    private func token(access: String, refresh: String) -> ChatGPTPlanTokenResponse {
        ChatGPTPlanTokenResponse(accessToken: access, refreshToken: refresh, idToken: "id", expiresIn: 3_600, scope: "openid chatgpt.tokens.use.direct")
    }
}

private final class SessionBox: @unchecked Sendable {
    var session: ChatGPTPlanSession?
    init(session: ChatGPTPlanSession?) { self.session = session }
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
