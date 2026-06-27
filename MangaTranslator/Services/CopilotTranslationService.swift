import Foundation
import CryptoKit

struct CopilotResolvedSession: Sendable {
    let modelID: String
    let sessionToken: String
    let expiresAt: Date?
}

enum CopilotProtocolError: LocalizedError, Equatable {
    case invalidModelSession

    var errorDescription: String? {
        "GitHub Copilot returned an invalid model session."
    }
}

actor CopilotAutoSessionResolver {
    static let shared = CopilotAutoSessionResolver()

    private struct Key: Hashable {
        let host: URL
        let accountDigest: String
        let modelHints: [String]
    }

    private struct HostAccount: Hashable {
        let host: URL
        let accountDigest: String
    }

    private struct InFlight {
        let id: UUID
        let generation: UInt64
        let task: Task<(Data, URLResponse), Error>
    }

    private let now: @Sendable () -> Date
    private let debugLogger: DebugLogger
    private var sessions: [Key: CopilotResolvedSession] = [:]
    private var inFlight: [Key: InFlight] = [:]
    private var generations: [Key: UInt64] = [:]
    private var activeAccountByHost: [URL: String] = [:]
    private var activeHintsByAccount: [HostAccount: [String]] = [:]

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        debugLogger: DebugLogger = .shared
    ) {
        self.now = now
        self.debugLogger = debugLogger
    }

    func resolve(
        token: String,
        host: URL,
        modelHints: [String],
        urlSession: URLSession
    ) async throws -> CopilotResolvedSession {
        try Task.checkCancellation()
        let key = Key(
            host: host,
            accountDigest: Self.digest(token),
            modelHints: modelHints
        )
        prepare(for: key)
        let generation = generations[key, default: 0]
        var refreshToken: String?
        if let cached = sessions[key], let expiresAt = cached.expiresAt {
            let remaining = expiresAt.timeIntervalSince(now())
            if remaining > 300 {
                return cached
            }
            if remaining > 0 {
                refreshToken = cached.sessionToken
            } else {
                sessions[key] = nil
            }
        }
        struct Response: Decodable {
            let selectedModel: String
            let availableModels: [String]
            let sessionToken: String
            let expiresAt: Double?

            enum CodingKeys: String, CodingKey {
                case selectedModel = "selected_model"
                case availableModels = "available_models"
                case sessionToken = "session_token"
                case expiresAt = "expires_at"
            }
        }

        var request = URLRequest(url: host.appending(path: "models/session"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CopilotEnvironment.copilotIntegrationID, forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue(CopilotEnvironment.copilotAPIVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if let refreshToken {
            request.setValue(refreshToken, forHTTPHeaderField: "Copilot-Session-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "auto_mode": ["model_hints": modelHints]
        ])

        let data: Data
        let response: URLResponse
        let flight: InFlight
        if let existing = inFlight[key], existing.generation == generation {
            flight = existing
        } else {
            let createdTask = Task { try await urlSession.data(for: request) }
            let created = InFlight(id: UUID(), generation: generation, task: createdTask)
            inFlight[key] = created
            flight = created
        }
        do {
            (data, response) = try await flight.task.value
            removeInFlight(key: key, id: flight.id)
            try Task.checkCancellation()
        } catch let error as URLError where error.code == .cancelled {
            removeInFlight(key: key, id: flight.id)
            if refreshToken != nil, generations[key, default: 0] == generation { sessions[key] = nil }
            throw error
        } catch is CancellationError {
            removeInFlight(key: key, id: flight.id)
            if refreshToken != nil, generations[key, default: 0] == generation { sessions[key] = nil }
            throw CancellationError()
        } catch {
            removeInFlight(key: key, id: flight.id)
            if generations[key, default: 0] == generation,
               refreshToken != nil,
               let cached = sessions[key],
               let expiresAt = cached.expiresAt,
               expiresAt > now() {
                return cached
            }
            if generations[key, default: 0] == generation { sessions[key] = nil }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        if http.statusCode != 200 {
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .copilot,
                providerDisplayName: TranslationEngine.githubCopilot.displayName,
                statusCode: http.statusCode,
                responseData: data
            )
            debugLogger.logAPIError(
                sanitized,
                category: .translationCopilot,
                endpoint: host.appending(path: "models/session").absoluteString
            )
            if refreshToken != nil, http.statusCode == 401 {
                guard generations[key, default: 0] == generation else {
                    throw TranslationError.apiError(sanitized)
                }
                sessions[key] = nil
                return try await resolve(
                    token: token,
                    host: host,
                    modelHints: modelHints,
                    urlSession: urlSession
                )
            }
            if refreshToken != nil, (500..<600).contains(http.statusCode) {
                if generations[key, default: 0] == generation,
                   let cached = sessions[key],
                   let expiresAt = cached.expiresAt,
                   expiresAt > now() {
                    return cached
                }
                if generations[key, default: 0] == generation { sessions[key] = nil }
            }
            if refreshToken != nil, generations[key, default: 0] == generation {
                sessions[key] = nil
            }
            throw TranslationError.apiError(sanitized)
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            if refreshToken != nil, generations[key, default: 0] == generation { sessions[key] = nil }
            throw CopilotProtocolError.invalidModelSession
        }
        guard !decoded.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !decoded.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              decoded.availableModels.contains(decoded.selectedModel),
              modelHints.contains(decoded.selectedModel),
              decoded.expiresAt.map({ $0 > now().timeIntervalSince1970 }) != false else {
            if refreshToken != nil, generations[key, default: 0] == generation { sessions[key] = nil }
            throw CopilotProtocolError.invalidModelSession
        }
        let resolved = CopilotResolvedSession(
            modelID: decoded.selectedModel,
            sessionToken: decoded.sessionToken,
            expiresAt: decoded.expiresAt.map { Date(timeIntervalSince1970: $0) }
        )
        if generations[key, default: 0] == generation {
            if resolved.expiresAt != nil {
                sessions[key] = resolved
            } else {
                sessions[key] = nil
            }
        }
        return resolved
    }

    func invalidate(token: String, host: URL, modelHints: [String]) {
        let key = Key(host: host, accountDigest: Self.digest(token), modelHints: modelHints)
        invalidate(key, cancelInFlight: false)
    }

    private func prepare(for key: Key) {
        let currentTime = now()
        sessions = sessions.filter { _, session in
            session.expiresAt.map { $0 > currentTime } == true
        }

        if let activeDigest = activeAccountByHost[key.host], activeDigest != key.accountDigest {
            evict { $0.host == key.host }
            activeHintsByAccount = activeHintsByAccount.filter { $0.key.host != key.host }
        }
        activeAccountByHost[key.host] = key.accountDigest

        let hostAccount = HostAccount(host: key.host, accountDigest: key.accountDigest)
        if let activeHints = activeHintsByAccount[hostAccount], activeHints != key.modelHints {
            evict { $0.host == key.host && $0.accountDigest == key.accountDigest }
        }
        activeHintsByAccount[hostAccount] = key.modelHints
    }

    private func evict(where predicate: (Key) -> Bool) {
        let keys = Set(sessions.keys.filter(predicate))
            .union(inFlight.keys.filter(predicate))
            .union(generations.keys.filter(predicate))
        for key in keys {
            invalidate(key, cancelInFlight: true)
        }
    }

    private func invalidate(_ key: Key, cancelInFlight: Bool) {
        sessions[key] = nil
        generations[key, default: 0] &+= 1
        if let flight = inFlight.removeValue(forKey: key), cancelInFlight {
            flight.task.cancel()
        }
    }

    private func removeInFlight(key: Key, id: UUID) {
        if inFlight[key]?.id == id {
            inFlight[key] = nil
        }
    }

    private static func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CopilotTranslationService: TranslationService {
    let engine = TranslationEngine.githubCopilot
    private let model: String
    private let urlSession: URLSession
    private let catalogStore: CopilotModelCatalogStore
    private let sessionResolver: CopilotAutoSessionResolver
    private let debugLogger: DebugLogger
    private let baseURLs = [
        "https://api.individual.githubcopilot.com",
        "https://api.githubcopilot.com"
    ]

    private struct AutoClientContext {
        let client: ChatCompletionsClient
        let host: URL
        let modelHints: [String]
    }

    init(
        model: String,
        urlSession: URLSession = .shared,
        catalogStore: CopilotModelCatalogStore = .shared,
        sessionResolver: CopilotAutoSessionResolver = .shared,
        debugLogger: DebugLogger = .shared
    ) {
        self.model = model
        self.urlSession = urlSession
        self.catalogStore = catalogStore
        self.sessionResolver = sessionResolver
        self.debugLogger = debugLogger
    }

    private func makeClient(
        baseURL: String,
        model: String? = nil,
        sessionToken: String? = nil
    ) -> ChatCompletionsClient {
        var headers = ["Copilot-Integration-Id": CopilotEnvironment.copilotIntegrationID]
        if let sessionToken {
            headers["Copilot-Session-Token"] = sessionToken
            headers["X-GitHub-Api-Version"] = CopilotEnvironment.copilotAPIVersion
        }
        return ChatCompletionsClient(
            endpoint: URL(string: baseURL)!,
            model: model ?? self.model,
            extraHeaders: headers,
            provider: .copilot,
            providerDisplayName: TranslationEngine.githubCopilot.displayName,
            category: .translationCopilot,
            urlSession: urlSession,
            apiErrorRetryClassifier: { (500..<600).contains($0.statusCode) },
            debugLogger: debugLogger
        )
    }

    private func makeAutoClient(token: String, host: URL) async throws -> AutoClientContext {
        let models = try await catalogStore.models(host: host, token: token) {
            try await CopilotEnvironment.fetchModelsFromEndpoint(
                token: token,
                urlString: host.appending(path: "models").absoluteString,
                session: urlSession
            )
        }
        guard !models.isEmpty else { throw TranslationError.invalidResponse }
        let catalog = CopilotModelCatalog(models: models)
        guard !catalog.autoHintModelIDs.isEmpty else {
            throw CopilotCatalogSelectionError.noCompatibleModels
        }
        let resolved = try await sessionResolver.resolve(
            token: token,
            host: host,
            modelHints: catalog.autoHintModelIDs,
            urlSession: urlSession
        )
        return AutoClientContext(
            client: makeClient(
                baseURL: host.absoluteString,
                model: resolved.modelID,
                sessionToken: resolved.sessionToken
            ),
            host: host,
            modelHints: catalog.autoHintModelIDs
        )
    }

    private func withAutoRecovery<T>(
        token: String,
        host: URL,
        _ operation: (ChatCompletionsClient) async throws -> T
    ) async throws -> T {
        let context = try await makeAutoClient(token: token, host: host)
        do {
            return try await operation(context.client)
        } catch TranslationError.apiError(let error) {
            let isCompatibilityFailure = error.code == "model_not_supported"
                || error.code == "unsupported_api_for_model"
            guard isCompatibilityFailure || error.statusCode == 401 else {
                throw TranslationError.apiError(error)
            }
            await sessionResolver.invalidate(token: token, host: context.host, modelHints: context.modelHints)
            if isCompatibilityFailure {
                await catalogStore.invalidate(host: context.host, token: token)
            }
            let replacement = try await makeAutoClient(token: token, host: host)
            return try await operation(replacement.client)
        }
    }

    private func withAutoHostFallback<T>(
        token: String,
        _ operation: (ChatCompletionsClient) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for host in CopilotEnvironment.catalogHosts {
            do {
                return try await withAutoRecovery(token: token, host: host, operation)
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch is CancellationError {
                throw CancellationError()
            } catch TranslationError.apiError(let error)
                where (400..<500).contains(error.statusCode) && error.statusCode != 404 {
                throw TranslationError.apiError(error)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CopilotCatalogSelectionError.noCompatibleModels
    }

    private func withExplicitHostFallback<T>(
        token: String,
        _ operation: (ChatCompletionsClient) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var foundModel = false
        for host in CopilotEnvironment.catalogHosts {
            do {
                let models = try await catalogStore.models(host: host, token: token) {
                    try await CopilotEnvironment.fetchModelsFromEndpoint(
                        token: token,
                        urlString: host.appending(path: "models").absoluteString,
                        session: urlSession
                    )
                }
                guard !models.isEmpty else {
                    lastError = TranslationError.invalidResponse
                    continue
                }
                let catalog = CopilotModelCatalog(models: models)
                guard catalog.selectableModels.contains(where: { $0.id == model }) else {
                    continue
                }
                foundModel = true
                return try await operation(makeClient(baseURL: host.absoluteString))
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch is CancellationError {
                throw CancellationError()
            } catch TranslationError.apiError(let error)
                where (400..<500).contains(error.statusCode) && error.statusCode != 404 {
                throw TranslationError.apiError(error)
            } catch {
                lastError = error
            }
        }
        if !foundModel, lastError == nil {
            throw CopilotCatalogSelectionError.modelUnavailable(model)
        }
        throw lastError ?? TranslationError.invalidResponse
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard case .available(let token) = CopilotEnvironment.check() else {
            debugLogger.log("Translation failed: Copilot token unavailable", level: .error, category: .translationCopilot)
            throw TranslationError.missingAPIKey(.githubCopilot)
        }

        return try await translate(
            bubbles: bubbles,
            from: source,
            to: target,
            context: context,
            token: token
        )
    }

    /// Internal entry point used by tests so they can bypass `CopilotEnvironment.check()`.
    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext,
        token: String
    ) async throws -> TranslationOutput {
        try Task.checkCancellation()
        if model == CopilotModel.auto.id {
            return try await withAutoHostFallback(token: token) { client in
                try await client.translate(
                    bubbles: bubbles,
                    from: source,
                    to: target,
                    context: context,
                    authToken: token
                )
            }
        }

        return try await withExplicitHostFallback(token: token) { client in
            try await client.translate(
                bubbles: bubbles,
                from: source,
                to: target,
                context: context,
                authToken: token
            )
        }
    }

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        guard case .available(let token) = CopilotEnvironment.check() else {
            debugLogger.log("translateBatch failed: Copilot token unavailable", level: .error, category: .translationCopilot)
            throw TranslationError.missingAPIKey(.githubCopilot)
        }
        return try await translateBatch(
            pageInputs: pageInputs,
            from: source,
            to: target,
            priorContext: priorContext,
            token: token
        )
    }

    /// Internal entry point used by tests so they can bypass `CopilotEnvironment.check()`
    /// the same way the per-page error tests bypass it via `callAPI`.
    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext,
        token: String
    ) async throws -> [BatchPageOutput] {
        try Task.checkCancellation()
        if model == CopilotModel.auto.id {
            return try await withAutoHostFallback(token: token) { client in
                try await client.translateBatch(
                    pageInputs: pageInputs,
                    from: source,
                    to: target,
                    priorContext: priorContext,
                    authToken: token
                )
            }
        }

        return try await withExplicitHostFallback(token: token) { client in
            try await client.translateBatch(
                pageInputs: pageInputs,
                from: source,
                to: target,
                priorContext: priorContext,
                authToken: token
            )
        }
    }

    /// Internal access so provider error tests can drive the non-2xx path
    /// without requiring `CopilotEnvironment.check()` to succeed in CI.
    func callAPI(systemPrompt: String, userPrompt: String, token: String) async throws -> String {
        try await makeClient(baseURL: baseURLs[0]).callAPI(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            authToken: token,
            maxTokens: ChatCompletionsClient.estimatedMaxTokens(bubbleCount: 1, pageCount: 1)
        )
    }
}
