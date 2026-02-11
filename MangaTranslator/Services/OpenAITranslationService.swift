import Foundation

struct OpenAITranslationService: TranslationService {
    let engine = TranslationEngine.openAI
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
        to target: Language
    ) async throws -> [TranslatedBubble] {
        guard let apiKey = keychainService.retrieve(for: .openAI) else {
            throw TranslationError.missingAPIKey(.openAI)
        }

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        for attempt in 0...maxRetries {
            let responseText = try await callAPI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                apiKey: apiKey
            )

            if let parsed = try? LLMResponseParser.parse(responseText, bubbles: bubbles) {
                return parsed
            }

            if attempt == maxRetries {
                return LLMResponseParser.fallbackParse(responseText, bubbles: bubbles)
            }
        }

        return LLMResponseParser.fallbackParse("", bubbles: bubbles)
    }

    private func callAPI(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError(errorText)
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
