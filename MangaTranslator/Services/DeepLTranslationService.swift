import Foundation

struct DeepLTranslationService: TranslationService {
    let engine = TranslationEngine.deepL
    /// DeepL `/v2/translate` accepts at most 50 entries in the `text` array.
    private static let maxTextsPerRequest = 50
    private let keychainService: KeychainService
    private let urlSession: URLSession

    init(
        keychainService: KeychainService = KeychainService(),
        urlSession: URLSession = .shared
    ) {
        self.keychainService = keychainService
        self.urlSession = urlSession
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard let apiKey = keychainService.retrieve(for: .deepL) else {
            DebugLogger.shared.log("Translation failed: missing API key", level: .error, category: .translationDeepL)
            throw TranslationError.missingAPIKey(.deepL)
        }

        DebugLogger.shared.logAPIDiagnostic(
            "Translation started: bubbles=\(bubbles.count) \(source.rawValue)→\(target.rawValue)",
            category: .translationDeepL
        )

        let terms = context.glossaryTerms
        var results: [TranslatedBubble] = []
        for chunkStart in stride(from: 0, to: bubbles.count, by: Self.maxTextsPerRequest) {
            let chunk = bubbles[chunkStart..<min(chunkStart + Self.maxTextsPerRequest, bubbles.count)]
            let textsToSend = chunk.map { GlossarySubstitution.applyXML(to: $0.text, terms: terms) }
            let translatedTexts = try await translateTexts(
                textsToSend, from: source, to: target, apiKey: apiKey, useXML: !terms.isEmpty
            )
            for (bubble, translated) in zip(chunk, translatedTexts) {
                results.append(TranslatedBubble(
                    bubble: bubble,
                    translatedText: GlossarySubstitution.revertXML(translated, terms: terms),
                    index: bubble.index
                ))
            }
        }
        DebugLogger.shared.logAPIDiagnostic(
            "Translation completed: bubbles=\(results.count)",
            category: .translationDeepL, statusCode: 200
        )
        return TranslationOutput(bubbles: results, detectedTerms: [])
    }

    /// Translates up to ``maxTextsPerRequest`` texts in one API call.
    /// DeepL returns translations in the same order as they are requested.
    private func translateTexts(
        _ texts: [String], from source: Language, to target: Language, apiKey: String, useXML: Bool
    ) async throws -> [String] {
        let host = apiKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        let url = URL(string: "https://\(host)/v2/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "text": texts,
            "source_lang": deepLLanguageCode(source),
            "target_lang": deepLLanguageCode(target)
        ]
        if useXML {
            body["tag_handling"] = "xml"
            body["ignore_tags"] = ["x"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .deepL,
                providerDisplayName: TranslationEngine.deepL.displayName,
                statusCode: statusCode,
                responseData: data
            )
            DebugLogger.shared.logAPIError(
                sanitized,
                category: .translationDeepL,
                endpoint: url.absoluteString
            )
            throw TranslationError.apiError(sanitized)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let translations = json?["translations"] as? [[String: Any]]
        let translatedTexts = translations?.compactMap { $0["text"] as? String }
        guard let translatedTexts, translatedTexts.count == texts.count else {
            throw TranslationError.invalidResponse
        }

        return translatedTexts
    }

    private func deepLLanguageCode(_ language: Language) -> String {
        switch language {
        case .ja: return "JA"
        case .en: return "EN"
        case .fr: return "FR"
        case .de: return "DE"
        case .id: return "ID"
        case .ko: return "KO"
        case .ptBR: return "PT-BR"
        case .zhHans: return "ZH-HANS"
        case .es: return "ES"
        case .zhHant: return "ZH-HANT"
        case .vi: return "VI"
        }
    }
}
