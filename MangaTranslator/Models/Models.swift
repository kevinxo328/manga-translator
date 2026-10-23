import Foundation
import CoreGraphics
import AppKit
import CryptoKit

enum Language: String, CaseIterable, Identifiable, Codable {
    case ja = "ja"
    case en = "en"
    case zhHant = "zh-Hant"
    case fr = "fr"
    case de = "de"
    case id = "id"
    case ko = "ko"
    case ptBR = "pt-BR"
    case zhHans = "zh-Hans"
    case es = "es"
    case vi = "vi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "🇺🇸 English"
        case .fr: return "🇫🇷 French"
        case .de: return "🇩🇪 German"
        case .id: return "🇮🇩 Indonesian"
        case .ja: return "🇯🇵 Japanese"
        case .ko: return "🇰🇷 Korean"
        case .ptBR: return "🇧🇷 Portuguese (Brazil)"
        case .zhHans: return "🇨🇳 Simplified Chinese"
        case .es: return "🇪🇸 Spanish"
        case .zhHant: return "🇹🇼 Traditional Chinese"
        case .vi: return "🇻🇳 Vietnamese"
        }
    }

    // OCR currently supports Japanese and English as source languages only.
    static let sourceLanguages: [Language] = [.en, .ja]

    static let targetLanguages: [Language] = [
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
    ]
}

enum TranslationEngine: String, CaseIterable, Identifiable, Codable {
    case deepL = "deepl"
    case google = "google"
    case openAI = "openai"
    case chatGPTPlan = "chatgpt-plan"
    case githubCopilot = "github-copilot"

    var id: String { rawValue }

    var displayName: String { TranslationEngineRegistry.descriptor(for: self).displayName }

    var requiresAPIKey: Bool { TranslationEngineRegistry.descriptor(for: self).requiresAPIKey }

    var usesRecentPageContext: Bool { TranslationEngineRegistry.descriptor(for: self).usesRecentPageContext }
}

struct TranslationEngineDescriptor: Equatable, Identifiable {
    let engine: TranslationEngine
    let displayName: String
    let requiresAPIKey: Bool
    let usesRecentPageContext: Bool

    var id: TranslationEngine { engine }
}

enum TranslationEngineRegistry {
    static let descriptors: [TranslationEngineDescriptor] = [
        TranslationEngineDescriptor(engine: .deepL, displayName: "DeepL", requiresAPIKey: true, usesRecentPageContext: false),
        TranslationEngineDescriptor(engine: .google, displayName: "Google Translate", requiresAPIKey: true, usesRecentPageContext: false),
        TranslationEngineDescriptor(engine: .openAI, displayName: "OpenAI Compatible", requiresAPIKey: true, usesRecentPageContext: true),
        TranslationEngineDescriptor(engine: .chatGPTPlan, displayName: "ChatGPT Plan (Preview)", requiresAPIKey: false, usesRecentPageContext: true),
        TranslationEngineDescriptor(engine: .githubCopilot, displayName: "GitHub Copilot", requiresAPIKey: false, usesRecentPageContext: true)
    ]

    static var engines: [TranslationEngine] { descriptors.map(\.engine) }

    static var credentialDescriptors: [TranslationEngineDescriptor] {
        descriptors.filter(\.requiresAPIKey)
    }

    static func descriptor(for engine: TranslationEngine) -> TranslationEngineDescriptor {
        guard let descriptor = descriptors.first(where: { $0.engine == engine }) else {
            preconditionFailure("Missing translation-engine descriptor for \(engine.rawValue)")
        }
        return descriptor
    }
}

enum TranslationPipelineLimits {
    static let maximumConcurrentPages = 3
}

/// The complete OAuth credential lifecycle for the one linked ChatGPT account.
/// It must only be persisted in protected storage and is intentionally opaque in diagnostics.
struct ChatGPTPlanSession: Codable, Equatable, Sendable, CustomStringConvertible {
    let email: String
    let subject: String
    let clientID: String
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scopes: Set<String>
    let selectedModel: String?

    init(
        email: String,
        subject: String,
        clientID: String,
        idToken: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        scopes: Set<String>,
        selectedModel: String? = nil
    ) {
        self.email = email
        self.subject = subject
        self.clientID = clientID
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.selectedModel = selectedModel
    }

    var description: String { "[REDACTED]" }

    var isAuthorizedForPlanUsage: Bool {
        scopes.contains("chatgpt.tokens.use.direct")
    }
}

struct ChatGPTPlanAuthorizationAttempt: Sendable {
    let state: String
    let nonce: String
    let verifier: String
    let redirectURI: URL
    let clientID: String
    let isNewRegistration: Bool

    static func make(redirectURI: URL, issuedClientID: String? = nil) -> ChatGPTPlanAuthorizationAttempt {
        ChatGPTPlanAuthorizationAttempt(
            state: randomURLSafeValue(), nonce: randomURLSafeValue(), verifier: randomURLSafeValue(),
            redirectURI: redirectURI, clientID: issuedClientID ?? "dynamic_agent_client",
            isNewRegistration: issuedClientID == nil
        )
    }

    var codeChallenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func randomURLSafeValue() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

enum ChatGPTPlanOAuthError: LocalizedError, Equatable {
    case invalidCallback
    case stateMismatch
    case authorizationDenied
    case missingIssuedClientID
    case unexpectedClientID
    case identityMismatch
    case missingPlanScope
    case browserLaunchFailed
    case tokenRequestFailed(statusCode: Int)
    case invalidIDTokenSignature

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "ChatGPT sign-in was cancelled in the browser."
        case .stateMismatch:
            return "ChatGPT returned a callback for a different sign-in attempt. Start sign-in again."
        case .missingIssuedClientID, .unexpectedClientID:
            return "ChatGPT did not complete client registration. Start sign-in again."
        case .identityMismatch:
            return "ChatGPT returned an invalid sign-in identity. Start sign-in again."
        case .invalidIDTokenSignature:
            return "ChatGPT returned an ID token that could not be verified. Start sign-in again."
        case .missingPlanScope:
            return "ChatGPT Plan permission was not granted. Enable it during sign-in and try again."
        case .browserLaunchFailed:
            return "Couldn’t open the browser for ChatGPT sign-in."
        case .tokenRequestFailed(let statusCode):
            return "ChatGPT sign-in could not exchange its authorization code (HTTP \(statusCode)). Start sign-in again."
        case .invalidCallback:
            return "ChatGPT did not return a valid sign-in callback. Start sign-in again."
        }
    }
}

struct ChatGPTPlanAuthorizationCallback: Sendable, Equatable {
    let code: String
    let clientID: String?
}

enum ChatGPTPlanOAuth {
    static let authorizationEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let resource = "https://api.openai.com/v1"
    static let requiredScopes = ["openid", "profile", "email", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]

    static func authorizationURL(for attempt: ChatGPTPlanAuthorizationAttempt, hostID: String) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: attempt.clientID),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: attempt.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: requiredScopes.joined(separator: " ")),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "nonce", value: attempt.nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: attempt.codeChallenge)
        ]
        if attempt.isNewRegistration { items.append(URLQueryItem(name: "agent_name_hint", value: "MangaTranslator")) }
        components.queryItems = items
        return components.url!
    }

    static func validate(callbackURL: URL, for attempt: ChatGPTPlanAuthorizationAttempt) throws -> ChatGPTPlanAuthorizationCallback {
        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else { throw ChatGPTPlanOAuthError.invalidCallback }
        let values = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
        guard values["state"] == attempt.state else { throw ChatGPTPlanOAuthError.stateMismatch }
        if values["error"] != nil { throw ChatGPTPlanOAuthError.authorizationDenied }
        guard let code = values["code"], !code.isEmpty else { throw ChatGPTPlanOAuthError.invalidCallback }
        let callbackClientID = values["client_id"]
        if attempt.isNewRegistration && (callbackClientID == nil || callbackClientID == "dynamic_agent_client") { throw ChatGPTPlanOAuthError.missingIssuedClientID }
        if !attempt.isNewRegistration, let callbackClientID, callbackClientID != attempt.clientID { throw ChatGPTPlanOAuthError.unexpectedClientID }
        return ChatGPTPlanAuthorizationCallback(code: code, clientID: callbackClientID)
    }

    static func identity(from idToken: String, expectedNonce: String, clientID: String, now: Date = Date()) throws -> (email: String, subject: String) {
        let parts = idToken.split(separator: ".")
        guard parts.count == 3,
              let payload = Data(base64URLEncoded: String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              claims["nonce"] as? String == expectedNonce,
              claims["iss"] as? String == "https://auth.openai.com",
              claims["email_verified"] as? Bool == true,
              (claims["aud"] as? String == clientID || (claims["aud"] as? [String])?.contains(clientID) == true),
              (claims["exp"] as? TimeInterval ?? 0) > now.timeIntervalSince1970,
              let email = claims["email"] as? String,
              let subject = claims["sub"] as? String,
              !email.isEmpty, !subject.isEmpty else {
            throw ChatGPTPlanOAuthError.identityMismatch
        }
        return (email, subject)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        let padding = String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + padding)
    }
}

struct CopilotModel: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String?
    let pickerEnabled: Bool?
    let supportedEndpoints: Set<String>
    let capabilityType: String?

    static let auto = CopilotModel(id: "auto", name: "Auto", category: nil)

    init(
        id: String,
        name: String,
        category: String?,
        pickerEnabled: Bool? = nil,
        supportedEndpoints: Set<String> = [],
        capabilityType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.pickerEnabled = pickerEnabled
        self.supportedEndpoints = supportedEndpoints
        self.capabilityType = capabilityType
    }

    var isChatCompletionsCompatible: Bool {
        supportedEndpoints.contains("/chat/completions")
    }

    var displayLabel: String {
        guard let category else { return name }
        let label: String
        switch category {
        case "powerful":   label = "Premium"
        case "lightweight": label = "Lite"
        default:           label = "Standard"
        }
        return "\(name) (\(label))"
    }
}

struct CopilotModelCatalog: Equatable {
    let models: [CopilotModel]

    var autoHintModelIDs: [String] {
        models.filter(\.isChatCompletionsCompatible).map(\.id)
    }

    var selectableModels: [CopilotModel] {
        models
            .filter { $0.isChatCompletionsCompatible && $0.pickerEnabled != false }
            .sorted { $0.name < $1.name }
    }
}

struct CopilotModelCatalogResult: Equatable {
    let host: URL
    let catalog: CopilotModelCatalog
}

enum CopilotCatalogPurpose: Equatable {
    case auto
    case explicit(modelID: String)
    case settings
}

enum CopilotCatalogSelectionError: LocalizedError, Equatable {
    case noCompatibleModels
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noCompatibleModels:
            return "No compatible Copilot models available."
        case .modelUnavailable(let modelID):
            return "Copilot model '\(modelID)' is unavailable."
        }
    }
}

enum CopilotModelLoadState: Equatable {
    case idle
    case loading
    case autoOnly
    case selectable([CopilotModel])
    case noCompatibleModels
    case failed(String)

    static func loaded(from catalog: CopilotModelCatalog) -> CopilotModelLoadState {
        let selectableModels = catalog.selectableModels
        if !selectableModels.isEmpty {
            return .selectable([.auto] + selectableModels)
        }
        if !catalog.autoHintModelIDs.isEmpty {
            return .autoOnly
        }
        return .noCompatibleModels
    }

    static func failed(from error: Error) -> CopilotModelLoadState {
        _ = error
        return .failed("Couldn’t load Copilot models.")
    }

    func normalizedCopilotModel(_ storedModelID: String) -> String {
        switch self {
        case .autoOnly:
            return CopilotModel.auto.id
        case .selectable(let models):
            return models.contains(where: { $0.id == storedModelID })
                ? storedModelID
                : CopilotModel.auto.id
        case .idle, .loading, .noCompatibleModels, .failed:
            return storedModelID
        }
    }
}

enum CopilotModelControls: Equatable {
    case none
    case loading
    case picker([CopilotModel])
    case noCompatibleModels
    case retry

    static func forState(_ state: CopilotModelLoadState) -> CopilotModelControls {
        switch state {
        case .idle:
            .none
        case .loading:
            .loading
        case .autoOnly:
            .picker([.auto])
        case .selectable(let models):
            .picker(models)
        case .noCompatibleModels:
            .noCompatibleModels
        case .failed:
            .retry
        }
    }
}

struct TextObservation: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let text: String
    let confidence: Float
}

struct BubbleCluster: Identifiable {
    let id: UUID
    // Mutable so Edit Mode's Move / Resize gestures can update geometry in
    // place on the working copy. Outside Edit Mode the field is treated as
    // immutable by convention; the OCR + translation pipeline constructs new
    // BubbleCluster values rather than mutating existing ones.
    var boundingBox: CGRect
    // Mutable so the Edit Mode commit pipeline can merge fresh OCR text into
    // an existing bubble via `withText(_:)`. Treated as immutable everywhere
    // else: OCR text is set at construction and replaced only on commit.
    var text: String
    let observations: [TextObservation]
    var index: Int = 0
    var isInverted: Bool = false
    // Tracks whether the user has touched this bubble's geometry in any Edit
    // Mode session — either by drawing it, moving it, or resizing it.
    // Single-bit semantics; sticky once set: the inverse of a Move / Resize
    // restores boundingBox only, never `isManual`. Cancel can
    // restore the pre-session value because Cancel restores the entire
    // snapshot, not because the flag is reset directly. Future "re-detect"
    // flows MUST consult this flag to decide which boxes to preserve.
    var isManual: Bool = false

    // Explicit initializer with `id` as a defaulted parameter so callers can
    // either let one be generated or supply an existing id (used by
    // `withText(_:)` and by the cache decoder where bubble identity is
    // re-minted on each read).
    init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        text: String,
        observations: [TextObservation],
        index: Int = 0,
        isInverted: Bool = false,
        isManual: Bool = false
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.text = text
        self.observations = observations
        self.index = index
        self.isInverted = isInverted
        self.isManual = isManual
    }

    // Convenience copy-with helper used by the Edit Mode commit pipeline when
    // merging fresh OCR text into an existing geometry. Returns a new value
    // with the same id, boundingBox, observations, index, isInverted, and
    // isManual but with a replaced `text`.
    func withText(_ newText: String) -> BubbleCluster {
        var copy = self
        copy.text = newText
        return copy
    }
}

struct MangaOCRPageResult {
    let bubbles: [BubbleCluster]
    let textPixelMask: CGImage?
    let lowConfidenceDetectionCount: Int
}

struct TranslatedBubble: Identifiable {
    let id = UUID()
    let bubble: BubbleCluster
    let translatedText: String
    let index: Int
}

enum PageState {
    case pending
    case processing
    case translated([TranslatedBubble])
    case error(String)
}

struct MangaPage: Identifiable {
    let id = UUID()
    let imageURL: URL
    var image: NSImage? = nil
    var imageHash: String? = nil
    var state: PageState = .pending
}

// MARK: - Edit Mode

// Reversible user actions in an Edit Mode session. Pushed onto an EditSession's
// undo stack on first application; popped and inverted by `Cmd+Z`; re-applied
// by `Cmd+Shift+Z`.
//
// `.delete` and `.unstageDelete` are set-based and idempotent on the session's
// `deletedBubbleIds` set: applying either twice has the same effect as once.
// This guarantees safe convergence when an `.unstageDelete` partially un-stages
// a member of an earlier `.multi([.delete, ...])` and the user later cycles
// through Cmd+Z / Cmd+Shift+Z.
//
// `.multi.inverse` MUST reverse its sub-inverses in opposite order so nested
// mutations unwind correctly.
indirect enum EditAction {
    case add(BubbleCluster)
    case delete(BubbleCluster)
    case unstageDelete(BubbleCluster)
    case move(id: UUID, from: CGRect, to: CGRect)
    case resize(id: UUID, from: CGRect, to: CGRect)
    case reorder(from: [UUID], to: [UUID])
    case multi([EditAction])
}

// Transactional, per-page edit state. Lives on TranslationViewModel as a
// private @MainActor property.
//
// `dirtyBubbleIds` is a UI-only cache for rendering the sidebar's "Modified"
// dirty visuals during the in-progress session. The commit pipeline derives
// OCR-dirty classification from current `boundingBox` vs. originalSnapshot
// `boundingBox` (§D3), NOT from this set; drift in `dirtyBubbleIds` affects
// only UI badges, never OCR cost or correctness.
//
// `originalPageState` is the PageState at session open (always `.translated`
// per the gating rule). On Cancel the page state is restored to this value
// — including the case where an in-session Commit previously failed and left
// the page in `.error`. Cancel clears that error.
struct EditSession {
    let pageId: UUID
    var workingBubbles: [BubbleCluster]
    var dirtyBubbleIds: Set<UUID>
    var deletedBubbleIds: Set<UUID>
    var selectedBubbleIds: Set<UUID>
    var undoStack: [EditAction]
    var redoStack: [EditAction]
    let originalSnapshot: [TranslatedBubble]
    let originalPageState: PageState

    init(
        pageId: UUID,
        workingBubbles: [BubbleCluster],
        originalSnapshot: [TranslatedBubble],
        originalPageState: PageState,
        dirtyBubbleIds: Set<UUID> = [],
        deletedBubbleIds: Set<UUID> = [],
        selectedBubbleIds: Set<UUID> = [],
        undoStack: [EditAction] = [],
        redoStack: [EditAction] = []
    ) {
        self.pageId = pageId
        self.workingBubbles = workingBubbles
        self.dirtyBubbleIds = dirtyBubbleIds
        self.deletedBubbleIds = deletedBubbleIds
        self.selectedBubbleIds = selectedBubbleIds
        self.undoStack = undoStack
        self.redoStack = redoStack
        self.originalSnapshot = originalSnapshot
        self.originalPageState = originalPageState
    }
}

extension EditAction {
    // Reverses the visible effect of this action on `session`.
    //
    // - `.move` / `.resize` inverse restores `boundingBox` only; `isManual`
    //   stays sticky (§D5).
    // - `.delete` / `.unstageDelete` inverses are set operations on
    //   `deletedBubbleIds` and are idempotent.
    // - `.multi` inverts its sub-actions in reverse order.
    func applyInverse(to session: inout EditSession) {
        switch self {
        case .add(let bubble):
            session.workingBubbles.removeAll { $0.id == bubble.id }
            session.deletedBubbleIds.remove(bubble.id)
            session.dirtyBubbleIds.remove(bubble.id)
            session.selectedBubbleIds.remove(bubble.id)
            EditAction.redensifyIndices(&session.workingBubbles)
        case .delete(let bubble):
            session.deletedBubbleIds.remove(bubble.id)
        case .unstageDelete(let bubble):
            session.deletedBubbleIds.insert(bubble.id)
        case .move(let id, let from, _), .resize(let id, let from, _):
            if let idx = session.workingBubbles.firstIndex(where: { $0.id == id }) {
                session.workingBubbles[idx].boundingBox = from
                // isManual intentionally NOT restored — sticky flag, §D5.

                // Best-effort UI cleanup: when undo restores `boundingBox`
                // to the snapshot's value, drop the dirty badge so the
                // sidebar reflects "current geometry == snapshot" again.
                // Commit correctness does NOT depend on this — the commit
                // pipeline derives OCR-dirty from geometry-vs-snapshot
                // directly (§D3); this branch only keeps the in-session
                // visual in sync.
                if let snapshot = session.originalSnapshot.first(where: { $0.bubble.id == id }),
                   snapshot.bubble.boundingBox == from {
                    session.dirtyBubbleIds.remove(id)
                }
            }
        case .reorder(let from, _):
            session.workingBubbles = EditAction.reorder(session.workingBubbles, byIds: from)
            EditAction.redensifyIndices(&session.workingBubbles)
        case .multi(let actions):
            for action in actions.reversed() {
                action.applyInverse(to: &session)
            }
        }
    }

    // Rewrites every entry's `index` to its current array position (0..<n).
    // Used after any reorder / insert / remove so downstream consumers see a
    // dense reading order.
    static func redensifyIndices(_ bubbles: inout [BubbleCluster]) {
        for i in bubbles.indices {
            bubbles[i].index = i
        }
    }

    // Returns `bubbles` reordered so its elements appear in the order given
    // by `ids`. Ids not present in `bubbles` are ignored; bubbles whose id
    // is not in `ids` are dropped — callers should pass an `ids` array that
    // covers every bubble in `bubbles`.
    static func reorder(_ bubbles: [BubbleCluster], byIds ids: [UUID]) -> [BubbleCluster] {
        var byId = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.id, $0) })
        return ids.compactMap { byId.removeValue(forKey: $0) }
    }
}

struct GlossaryTerm: Identifiable {
    let id: String
    let sourceTerm: String
    let targetTerm: String
    let autoDetected: Bool
}

struct Glossary: Identifiable {
    let id: String
    let name: String
}

struct TranslationContext {
    let glossaryTerms: [GlossaryTerm]
    let recentPageSummaries: [String]

    static let empty = TranslationContext(glossaryTerms: [], recentPageSummaries: [])
}

struct TranslationOutput {
    let bubbles: [TranslatedBubble]
    let detectedTerms: [GlossaryTerm]
}

extension [TranslatedBubble] {
    var sortedByIndex: [TranslatedBubble] {
        sorted { $0.index < $1.index }
    }
}

struct BatchPageInput {
    let pageId: String
    let bubbles: [BubbleCluster]
}

struct BatchPageOutput {
    let pageId: String
    let bubbles: [TranslatedBubble]
    let detectedTerms: [GlossaryTerm]
}

protocol TranslationService {
    var engine: TranslationEngine { get }
    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput]
}

extension TranslationService {
    // Default fallback used by engines that have not opted in to true multi-page batching
    // (DeepL, Google) and by test fakes that only implement the per-page method. The batch
    // scheduler may still route through this path; behaviour matches today's per-page loop.
    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        var outputs: [BatchPageOutput] = []
        outputs.reserveCapacity(pageInputs.count)
        for input in pageInputs {
            let output = try await translate(
                bubbles: input.bubbles,
                from: source,
                to: target,
                context: priorContext
            )
            outputs.append(BatchPageOutput(
                pageId: input.pageId,
                bubbles: output.bubbles,
                detectedTerms: output.detectedTerms
            ))
        }
        return outputs
    }
}
