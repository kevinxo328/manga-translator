import Foundation

struct GoogleTranslationService: TranslationService {
    let engine = TranslationEngine.google
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
        for bubble in bubbles {
            let textToSend = GlossarySubstitution.applyHTML(to: bubble.text, terms: terms)
            var translated = try await translateText(
                textToSend, from: source, to: target, apiKey: apiKey, useHTML: !terms.isEmpty
            )
            translated = GlossarySubstitution.revertHTML(translated, terms: terms)
            results.append(TranslatedBubble(
                bubble: bubble,
                translatedText: translated,
                index: bubble.index
            ))
        }
        DebugLogger.shared.logAPIDiagnostic(
            "Translation completed: bubbles=\(results.count)",
            category: .translationGoogle, statusCode: 200
        )
        return TranslationOutput(bubbles: results, detectedTerms: [])
    }

    private func translateText(
        _ text: String, from source: Language, to target: Language, apiKey: String, useHTML: Bool
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
        guard let translatedText = translations?.first?["translatedText"] as? String else {
            throw TranslationError.invalidResponse
        }

        return translatedText
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
