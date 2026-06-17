import Foundation

struct CopilotTranslationService: TranslationService {
    let engine = TranslationEngine.githubCopilot
    private let model: String
    private let urlSession: URLSession
    private let baseURLs = [
        "https://api.individual.githubcopilot.com",
        "https://api.githubcopilot.com"
    ]

    init(model: String, urlSession: URLSession = .shared) {
        self.model = model
        self.urlSession = urlSession
    }

    private func makeClient(baseURL: String) -> ChatCompletionsClient {
        ChatCompletionsClient(
            endpoint: URL(string: baseURL)!,
            model: model,
            extraHeaders: ["Copilot-Integration-Id": "copilot-developer-cli"],
            provider: .copilot,
            providerDisplayName: TranslationEngine.githubCopilot.displayName,
            category: .translationCopilot,
            urlSession: urlSession
        )
    }

    private func withEndpointFallback<T>(
        _ operation: (ChatCompletionsClient) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for baseURL in baseURLs {
            do {
                return try await operation(makeClient(baseURL: baseURL))
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
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
            DebugLogger.shared.log("Translation failed: Copilot token unavailable", level: .error, category: .translationCopilot)
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
        try await withEndpointFallback { client in
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
            DebugLogger.shared.log("translateBatch failed: Copilot token unavailable", level: .error, category: .translationCopilot)
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
        try await withEndpointFallback { client in
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
