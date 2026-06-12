import Foundation

struct GoogleTranslationService: TranslationService {
    let engine = TranslationEngine.google
    /// Cloud Translation v2 accepts at most 128 strings in the `q` array.
    private static let maxTextsPerRequest = 128
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
        guard let apiKey = keychainService.retrieve(for: .google) else {
            DebugLogger.shared.log("Translation failed: missing API key", level: .error, category: .translationGoogle)
            throw TranslationError.missingAPIKey(.google)
        }

        DebugLogger.shared.logAPIDiagnostic(
            "Translation started: bubbles=\(bubbles.count) \(source.rawValue)→\(target.rawValue)",
            category: .translationGoogle
        )

        let terms = context.glossaryTerms
        var results: [TranslatedBubble] = []
        for chunkStart in stride(from: 0, to: bubbles.count, by: Self.maxTextsPerRequest) {
            let chunk = bubbles[chunkStart..<min(chunkStart + Self.maxTextsPerRequest, bubbles.count)]
            let textsToSend = chunk.map { GlossarySubstitution.applyHTML(to: $0.text, terms: terms) }
            let translatedTexts = try await translateTexts(
                textsToSend, from: source, to: target, apiKey: apiKey, useHTML: !terms.isEmpty
            )
            for (bubble, translated) in zip(chunk, translatedTexts) {
                results.append(TranslatedBubble(
                    bubble: bubble,
                    translatedText: GlossarySubstitution.revertHTML(translated, terms: terms),
                    index: bubble.index
                ))
            }
        }
        DebugLogger.shared.logAPIDiagnostic(
            "Translation completed: bubbles=\(results.count)",
            category: .translationGoogle, statusCode: 200
        )
        return TranslationOutput(bubbles: results, detectedTerms: [])
    }

    /// Translates up to ``maxTextsPerRequest`` texts in one API call.
    /// The response `translations` list corresponds positionally to `q`.
    private func translateTexts(
        _ texts: [String], from source: Language, to target: Language, apiKey: String, useHTML: Bool
    ) async throws -> [String] {
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "q": texts,
            "source": googleLanguageCode(source),
            "target": googleLanguageCode(target),
            "format": useHTML ? "html" : "text"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .google,
                providerDisplayName: TranslationEngine.google.displayName,
                statusCode: statusCode,
                responseData: data
            )
            DebugLogger.shared.logAPIError(
                sanitized,
                category: .translationGoogle,
                endpoint: components.url?.absoluteString
            )
            throw TranslationError.apiError(sanitized)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let translations = dataObj?["translations"] as? [[String: Any]]
        let translatedTexts = translations?.compactMap { $0["translatedText"] as? String }
        guard let translatedTexts, translatedTexts.count == texts.count else {
            throw TranslationError.invalidResponse
        }

        return translatedTexts
    }

    private func googleLanguageCode(_ language: Language) -> String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        case .fr: return "fr"
        case .de: return "de"
        case .id: return "id"
        case .ko: return "ko"
        case .ptBR: return "pt-BR"
        case .zhHans: return "zh-CN"
        case .es: return "es"
        case .zhHant: return "zh-TW"
        case .vi: return "vi"
        }
    }
}
