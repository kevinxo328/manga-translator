import Foundation

struct CopilotTranslationService: TranslationService {
    let engine = TranslationEngine.githubCopilot
    private let model: String
    private let urlSession: URLSession
    private let baseURL = "https://api.individual.githubcopilot.com"

    init(model: String, urlSession: URLSession = .shared) {
        self.model = model
        self.urlSession = urlSession
    }

    private var client: ChatCompletionsClient {
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

        return try await client.translate(
            bubbles: bubbles,
            from: source,
            to: target,
            context: context,
            authToken: token
        )
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
        try await client.translateBatch(
            pageInputs: pageInputs,
            from: source,
            to: target,
            priorContext: priorContext,
            authToken: token
        )
    }

    /// Internal access so provider error tests can drive the non-2xx path
    /// without requiring `CopilotEnvironment.check()` to succeed in CI.
    func callAPI(systemPrompt: String, userPrompt: String, token: String) async throws -> String {
        try await client.callAPI(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            authToken: token,
            maxTokens: ChatCompletionsClient.estimatedMaxTokens(bubbleCount: 1, pageCount: 1)
        )
    }
}
