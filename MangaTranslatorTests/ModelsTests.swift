import Testing
import Foundation
@testable import MangaTranslator

@Test("ChatGPT Plan sessions redact account identity and renewable credentials")
func chatGPTPlanSessionRedactsSensitiveDiagnosticData() {
    let session = ChatGPTPlanSession(
        email: "reader@example.com",
        subject: "user-123",
        clientID: "oaiapp_123",
        idToken: "id-token-secret",
        accessToken: "access-token-secret",
        refreshToken: "refresh-token-secret",
        expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
        scopes: ["chatgpt.tokens.use.direct"]
    )

    #expect(session.description == "[REDACTED]")
    #expect(!session.description.contains(session.email))
    #expect(!session.description.contains(session.refreshToken))
}

@Test("ChatGPT Plan callback rejects a browser response for another sign-in attempt")
func chatGPTPlanCallbackRejectsMismatchedState() {
    let attempt = ChatGPTPlanAuthorizationAttempt(
        state: "expected-state", nonce: "nonce", verifier: "verifier",
        redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!,
        clientID: "dynamic_agent_client", isNewRegistration: true
    )

    #expect(throws: ChatGPTPlanOAuthError.stateMismatch) {
        try ChatGPTPlanOAuth.validate(
            callbackURL: URL(string: "http://127.0.0.1:1455/auth/callback?code=code&state=wrong&client_id=oaiapp_123")!,
            for: attempt
        )
    }
}

@Test("ChatGPT Plan authorization uses a UUID URN host identifier")
func chatGPTPlanAuthorizationUsesUUIDURNHostID() throws {
    let attempt = ChatGPTPlanAuthorizationAttempt(
        state: "state", nonce: "nonce", verifier: "verifier",
        redirectURI: URL(string: "http://127.0.0.1:1455/callback")!,
        clientID: "dynamic_agent_client", isNewRegistration: true
    )

    let url = ChatGPTPlanOAuth.authorizationURL(
        for: attempt,
        hostID: "urn:uuid:123e4567-e89b-12d3-a456-426614174000"
    )
    let values = Dictionary(uniqueKeysWithValues: try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(values["ext_agent_host_id"] == "urn:uuid:123e4567-e89b-12d3-a456-426614174000")
}

@Test("ChatGPT Plan OAuth errors explain the next safe action")
func chatGPTPlanOAuthErrorsAreActionable() {
    #expect(ChatGPTPlanOAuthError.authorizationDenied.errorDescription == "ChatGPT sign-in was cancelled in the browser.")
    #expect(ChatGPTPlanOAuthError.tokenRequestFailed(statusCode: 400).errorDescription == "ChatGPT sign-in could not exchange its authorization code (HTTP 400). Start sign-in again.")
}

@Test("ChatGPT Plan token claims must belong to the authorization attempt")
func chatGPTPlanTokenClaimsRejectMismatchedNonce() {
    #expect(throws: ChatGPTPlanOAuthError.identityMismatch) {
        try ChatGPTPlanOAuth.identity(
            from: "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InJlYWRlckBleGFtcGxlLmNvbSIsInN1YiI6InVzZXItMTIzIiwibm9uY2UiOiJ3cm9uZyJ9.signature",
            expectedNonce: "expected", clientID: "issued-client"
        )
    }
}

@Suite("Models")
struct ModelsTests {

    @Test("Translation engine registry defines display, credential, and context capabilities")
    func translationEngineRegistryDefinesCapabilities() {
        #expect(TranslationEngineRegistry.engines == [.deepL, .google, .openAI, .chatGPTPlan, .githubCopilot])
        #expect(TranslationEngineRegistry.engines == TranslationEngine.allCases)
        #expect(TranslationEngineRegistry.credentialDescriptors.map(\.engine) == [.deepL, .google, .openAI])
        #expect(TranslationEngine.deepL.displayName == "DeepL")
        #expect(TranslationEngine.google.requiresAPIKey)
        #expect(TranslationEngine.openAI.usesRecentPageContext)
        #expect(!TranslationEngine.githubCopilot.requiresAPIKey)
        #expect(TranslationEngine.githubCopilot.usesRecentPageContext)
        #expect(TranslationPipelineLimits.maximumConcurrentPages == 3)
    }

    @Test("Language.displayName returns correct display labels")
    func languageDisplayNameLabels() {
        #expect(Language.en.displayName == "🇺🇸 English")
        #expect(Language.fr.displayName == "🇫🇷 French")
        #expect(Language.de.displayName == "🇩🇪 German")
        #expect(Language.id.displayName == "🇮🇩 Indonesian")
        #expect(Language.ja.displayName == "🇯🇵 Japanese")
        #expect(Language.ko.displayName == "🇰🇷 Korean")
        #expect(Language.ptBR.displayName == "🇧🇷 Portuguese (Brazil)")
        #expect(Language.zhHans.displayName == "🇨🇳 Simplified Chinese")
        #expect(Language.es.displayName == "🇪🇸 Spanish")
        #expect(Language.zhHant.displayName == "🇹🇼 Traditional Chinese")
        #expect(Language.vi.displayName == "🇻🇳 Vietnamese")
    }

    @Test("Language.rawValue remains stable for persistence and routing")
    func languageRawValues() {
        #expect(Language.en.rawValue == "en")
        #expect(Language.fr.rawValue == "fr")
        #expect(Language.de.rawValue == "de")
        #expect(Language.id.rawValue == "id")
        #expect(Language.ja.rawValue == "ja")
        #expect(Language.ko.rawValue == "ko")
        #expect(Language.ptBR.rawValue == "pt-BR")
        #expect(Language.zhHans.rawValue == "zh-Hans")
        #expect(Language.es.rawValue == "es")
        #expect(Language.zhHant.rawValue == "zh-Hant")
        #expect(Language.vi.rawValue == "vi")
    }

    @Test("Language.allCases contains every persisted language case in declaration order")
    func allLanguageCases() {
        #expect(Language.allCases == [
            .ja,
            .en,
            .zhHant,
            .fr,
            .de,
            .id,
            .ko,
            .ptBR,
            .zhHans,
            .es,
            .vi
        ])
    }

    @Test("Language.sourceLanguages exposes only OCR-supported source languages in A-Z order")
    func sourceLanguagesContents() {
        // zhHant is a target-only language; exposing it here would break
        // the source language pickers in SettingsView and ContentView.
        #expect(Language.sourceLanguages == [.en, .ja])
        #expect(!Language.sourceLanguages.contains(.zhHant))
    }

    @Test("Language.targetLanguages exposes supported targets in A-Z order")
    func targetLanguagesContents() {
        #expect(Language.targetLanguages == [
            .en,
            .fr,
            .de,
            .id,
            .ja,
            .ko,
            .ptBR,
            .zhHans,
            .es,
            .zhHant,
            .vi
        ])
    }

    @Test("BubbleCluster.isInverted defaults to false for legacy initializers")
    func bubbleClusterIsInvertedDefault() {
        let bubble = BubbleCluster(boundingBox: .zero, text: "test", observations: [])
        #expect(bubble.isInverted == false)
    }

    @Test("MangaOCRPageResult with nil textPixelMask round-trips correctly")
    func mangaOCRPageResultNilMask() {
        let result = MangaOCRPageResult(bubbles: [], textPixelMask: nil, lowConfidenceDetectionCount: 0)
        #expect(result.bubbles.isEmpty)
        #expect(result.textPixelMask == nil)
        #expect(result.lowConfidenceDetectionCount == 0)
    }
}
