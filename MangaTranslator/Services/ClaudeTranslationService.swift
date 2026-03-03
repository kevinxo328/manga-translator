import Foundation

struct ClaudeTranslationService: TranslationService {
    let engine = TranslationEngine.claude
    private let keychainService: KeychainService
    private let model: String
    private let maxRetries = 2

    init(model: String, keychainService: KeychainService = KeychainService()) {
        self.model = model
        self.keychainService = keychainService
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard let apiKey = keychainService.retrieve(for: .claude) else {
            throw TranslationError.missingAPIKey(.claude)
        }

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target, context: context)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        for attempt in 0...maxRetries {
            let responseText = try await callAPI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                apiKey: apiKey
            )

            if let (parsed, detected) = try? LLMResponseParser.parse(responseText, bubbles: bubbles) {
                return TranslationOutput(bubbles: parsed, detectedTerms: detected)
            }

            if attempt == maxRetries {
                let (fallback, _) = LLMResponseParser.fallbackParse(responseText, bubbles: bubbles)
                return TranslationOutput(bubbles: fallback, detectedTerms: [])
            }
        }

        let (fallback, _) = LLMResponseParser.fallbackParse("", bubbles: bubbles)
        return TranslationOutput(bubbles: fallback, detectedTerms: [])
    }

    private func callAPI(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError(errorText)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        guard let text = content?.first?["text"] as? String else {
            throw TranslationError.invalidResponse
        }

        return text
    }
}
