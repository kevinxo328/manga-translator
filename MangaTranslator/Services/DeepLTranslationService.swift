import Foundation

struct DeepLTranslationService: TranslationService {
    let engine = TranslationEngine.deepL
    private let keychainService: KeychainService

    init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language
    ) async throws -> [TranslatedBubble] {
        guard let apiKey = keychainService.retrieve(for: .deepL) else {
            throw TranslationError.missingAPIKey(.deepL)
        }

        var results: [TranslatedBubble] = []
        for (index, bubble) in bubbles.enumerated() {
            let translated = try await translateText(
                bubble.text, from: source, to: target, apiKey: apiKey
            )
            results.append(TranslatedBubble(
                bubble: bubble,
                translatedText: translated,
                index: index
            ))
        }
        return results
    }

    private func translateText(
        _ text: String, from source: Language, to target: Language, apiKey: String
    ) async throws -> String {
        let url = URL(string: "https://api-free.deepl.com/v2/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": [text],
            "source_lang": deepLLanguageCode(source),
            "target_lang": deepLLanguageCode(target)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError(errorText)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let translations = json?["translations"] as? [[String: Any]]
        guard let translatedText = translations?.first?["text"] as? String else {
            throw TranslationError.invalidResponse
        }

        return translatedText
    }

    private func deepLLanguageCode(_ language: Language) -> String {
        switch language {
        case .ja: return "JA"
        case .en: return "EN"
        case .zhHant: return "ZH-HANT"
        }
    }
}
