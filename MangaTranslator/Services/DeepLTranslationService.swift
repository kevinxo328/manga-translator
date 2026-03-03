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
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard let apiKey = keychainService.retrieve(for: .deepL) else {
            throw TranslationError.missingAPIKey(.deepL)
        }

        let terms = context.glossaryTerms
        var results: [TranslatedBubble] = []
        for (index, bubble) in bubbles.enumerated() {
            let textToSend = GlossarySubstitution.applyXML(to: bubble.text, terms: terms)
            var translated = try await translateText(
                textToSend, from: source, to: target, apiKey: apiKey, useXML: !terms.isEmpty
            )
            translated = GlossarySubstitution.revertXML(translated, terms: terms)
            results.append(TranslatedBubble(
                bubble: bubble,
                translatedText: translated,
                index: index
            ))
        }
        return TranslationOutput(bubbles: results, detectedTerms: [])
    }

    private func translateText(
        _ text: String, from source: Language, to target: Language, apiKey: String, useXML: Bool
    ) async throws -> String {
        let host = apiKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        let url = URL(string: "https://\(host)/v2/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "text": [text],
            "source_lang": deepLLanguageCode(source),
            "target_lang": deepLLanguageCode(target)
        ]
        if useXML {
            body["tag_handling"] = "xml"
            body["ignore_tags"] = ["x"]
        }
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
