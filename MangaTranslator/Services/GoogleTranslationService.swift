import Foundation

struct GoogleTranslationService: TranslationService {
    let engine = TranslationEngine.google
    private let keychainService: KeychainService

    init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard let apiKey = keychainService.retrieve(for: .google) else {
            throw TranslationError.missingAPIKey(.google)
        }

        let (substituted, mapping) = GlossarySubstitution.apply(to: bubbles, terms: context.glossaryTerms)

        var results: [TranslatedBubble] = []
        for (index, bubble) in substituted.enumerated() {
            var translated = try await translateText(
                bubble.text, from: source, to: target, apiKey: apiKey
            )
            translated = GlossarySubstitution.revert(translated, mapping: mapping)
            results.append(TranslatedBubble(
                bubble: bubbles[index],
                translatedText: translated,
                index: index
            ))
        }
        return TranslationOutput(bubbles: results, detectedTerms: [])
    }

    private func translateText(
        _ text: String, from source: Language, to target: Language, apiKey: String
    ) async throws -> String {
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "q": text,
            "source": googleLanguageCode(source),
            "target": googleLanguageCode(target),
            "format": "text"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError(errorText)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let translations = dataObj?["translations"] as? [[String: Any]]
        guard let translatedText = translations?.first?["translatedText"] as? String else {
            throw TranslationError.invalidResponse
        }

        return translatedText
    }

    private func googleLanguageCode(_ language: Language) -> String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        case .zhHant: return "zh-TW"
        }
    }
}
