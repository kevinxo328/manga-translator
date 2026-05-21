import Foundation

struct OpenAITranslationService: TranslationService {
    let engine = TranslationEngine.openAI
    private let keychainService: KeychainService
    private let model: String
    private let baseURL: String
    private let urlSession: URLSession
    private let maxRetries = 2

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
        let sanitizedBaseURL = String(baseURL.reversed().drop(while: { $0 == "/" }).reversed())
        try BaseURLValidator.validate(sanitizedBaseURL)

        guard let apiKey = keychainService.retrieve(for: .openAI) else {
            DebugLogger.shared.log("Translation failed: missing API key", level: .error, category: .translationOpenAI)
            throw TranslationError.missingAPIKey(.openAI)
        }

        DebugLogger.shared.logAPIDiagnostic(
            "Translation started: bubbles=\(bubbles.count) \(source.rawValue)→\(target.rawValue)",
            category: .translationOpenAI, model: model, endpoint: sanitizedBaseURL
        )

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target, context: context)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        for attempt in 0...maxRetries {
            let responseText = try await callAPI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                apiKey: apiKey
            )

            if let (parsed, detected) = try? LLMResponseParser.parse(responseText, bubbles: bubbles) {
                DebugLogger.shared.logAPIDiagnostic(
                    "Translation completed: bubbles=\(parsed.count)",
                    category: .translationOpenAI, statusCode: 200, model: model
                )
                return TranslationOutput(bubbles: parsed, detectedTerms: detected)
            }

            if attempt == maxRetries {
                DebugLogger.shared.log("Translation response parse failed after \(maxRetries + 1) attempts, using fallback", level: .warning, category: .translationOpenAI)
                let (fallback, _) = LLMResponseParser.fallbackParse(responseText, bubbles: bubbles)
                return TranslationOutput(bubbles: fallback, detectedTerms: [])
            }
        }

        let (fallback, _) = LLMResponseParser.fallbackParse("", bubbles: bubbles)
        return TranslationOutput(bubbles: fallback, detectedTerms: [])
    }

    private func callAPI(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        let sanitizedBaseURL = String(baseURL.reversed().drop(while: { $0 == "/" }).reversed())
        let sanitizedModel = String(model.drop(while: { $0 == "/" }))
        let url = try BaseURLValidator.validate(sanitizedBaseURL).appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": sanitizedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .openAI,
                providerDisplayName: TranslationEngine.openAI.displayName,
                statusCode: statusCode,
                responseData: data
            )
            DebugLogger.shared.logAPIError(
                sanitized,
                category: .translationOpenAI,
                model: sanitizedModel,
                endpoint: sanitizedBaseURL
            )
            throw TranslationError.apiError(sanitized)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw TranslationError.invalidResponse
        }

        return content
    }
}
