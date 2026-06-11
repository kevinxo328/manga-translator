import Foundation

struct OpenAITranslationService: TranslationService {
    let engine = TranslationEngine.openAI
    private let keychainService: KeychainService
    private let model: String
    private let baseURL: String
    private let urlSession: URLSession

    init(
        model: String,
        baseURL: String,
        keychainService: KeychainService = KeychainService(),
        urlSession: URLSession = .shared
    ) {
        self.model = model
        self.baseURL = baseURL
        self.keychainService = keychainService
        self.urlSession = urlSession
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        let client = try makeClient()

        guard let apiKey = keychainService.retrieve(for: .openAI) else {
            DebugLogger.shared.log("Translation failed: missing API key", level: .error, category: .translationOpenAI)
            throw TranslationError.missingAPIKey(.openAI)
        }

        return try await client.translate(
            bubbles: bubbles,
            from: source,
            to: target,
            context: context,
            authToken: apiKey
        )
    }

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        let client = try makeClient()

        guard let apiKey = keychainService.retrieve(for: .openAI) else {
            DebugLogger.shared.log("translateBatch failed: missing API key", level: .error, category: .translationOpenAI)
            throw TranslationError.missingAPIKey(.openAI)
        }

        return try await client.translateBatch(
            pageInputs: pageInputs,
            from: source,
            to: target,
            priorContext: priorContext,
            authToken: apiKey
        )
    }

    private func makeClient() throws -> ChatCompletionsClient {
        let sanitizedBaseURL = BaseURLValidator.sanitized(baseURL)
        let endpoint = try BaseURLValidator.validate(sanitizedBaseURL)
        return ChatCompletionsClient(
            endpoint: endpoint,
            model: String(model.drop(while: { $0 == "/" })),
            provider: .openAI,
            providerDisplayName: TranslationEngine.openAI.displayName,
            category: .translationOpenAI,
            urlSession: urlSession
        )
    }
}
