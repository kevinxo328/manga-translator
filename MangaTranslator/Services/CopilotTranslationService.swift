import Foundation

struct CopilotTranslationService: TranslationService {
    let engine = TranslationEngine.githubCopilot
    private let model: String
    private let urlSession: URLSession
    private let maxRetries = 2
    private let baseURL = "https://api.individual.githubcopilot.com"

    init(model: String, urlSession: URLSession = .shared) {
        self.model = model
        self.urlSession = urlSession
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard case .available(let token) = CopilotEnvironment.check() else {
            DebugLogger.shared.log("Translation failed: Copilot token unavailable", level: .error, category: .translationCopilot)
            throw TranslationError.missingAPIKey(.githubCopilot)
        }

        DebugLogger.shared.logAPIDiagnostic(
            "Translation started: bubbles=\(bubbles.count) \(source.rawValue)→\(target.rawValue)",
            category: .translationCopilot, model: model, endpoint: baseURL
        )

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target, context: context)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        for attempt in 0...maxRetries {
            let responseText = try await callAPI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                token: token
            )

            if let (parsed, detected) = try? LLMResponseParser.parse(responseText, bubbles: bubbles) {
                DebugLogger.shared.logAPIDiagnostic(
                    "Translation completed: bubbles=\(parsed.count)",
                    category: .translationCopilot, statusCode: 200, model: model
                )
                return TranslationOutput(bubbles: parsed, detectedTerms: detected)
            }

            if attempt == maxRetries {
                DebugLogger.shared.log("Translation response parse failed after \(maxRetries + 1) attempts, using fallback", level: .warning, category: .translationCopilot)
                let (fallback, _) = LLMResponseParser.fallbackParse(responseText, bubbles: bubbles)
                return TranslationOutput(bubbles: fallback, detectedTerms: [])
            }
        }

        let (fallback, _) = LLMResponseParser.fallbackParse("", bubbles: bubbles)
        return TranslationOutput(bubbles: fallback, detectedTerms: [])
    }

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        guard case .available(let token) = CopilotEnvironment.check() else {
            DebugLogger.shared.log("translateBatch failed: Copilot token unavailable", level: .error, category: .translationCopilot)
            throw TranslationError.missingAPIKey(.githubCopilot)
        }
        return try await translateBatch(
            pageInputs: pageInputs,
            from: source,
            to: target,
            priorContext: priorContext,
            token: token
        )
    }

    /// Internal entry point used by tests so they can bypass `CopilotEnvironment.check()`
    /// the same way the per-page error tests bypass it via `callAPI`.
    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext,
        token: String
    ) async throws -> [BatchPageOutput] {
        DebugLogger.shared.logAPIDiagnostic(
            "translateBatch started: pages=\(pageInputs.count) \(source.rawValue)→\(target.rawValue)",
            category: .translationCopilot, model: model, endpoint: baseURL
        )

        let systemPrompt = LLMPrompt.multiPageSystemPrompt(from: source, to: target, context: priorContext)
        let userPrompt = LLMPrompt.multiPageUserPrompt(pageInputs: pageInputs)

        let maxAttempts = 2
        var lastError: Error?
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let responseText = try await callAPI(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    token: token
                )
                let outputs = try LLMResponseParser.parseMultiPage(responseText, pageInputs: pageInputs)
                DebugLogger.shared.logAPIDiagnostic(
                    "translateBatch completed: pages=\(outputs.count)",
                    category: .translationCopilot, statusCode: 200, model: model
                )
                return outputs
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    // 500ms backoff * 2^(attempt-1); only one retry per design.
                    let nanos: UInt64 = 500_000_000 * UInt64(1 << (attempt - 1))
                    try? await Task.sleep(nanoseconds: nanos)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? TranslationError.invalidResponse
    }

    /// Internal access so provider error tests can drive the non-2xx path
    /// without requiring `CopilotEnvironment.check()` to succeed in CI.
    func callAPI(systemPrompt: String, userPrompt: String, token: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("copilot-developer-cli", forHTTPHeaderField: "Copilot-Integration-Id")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .copilot,
                providerDisplayName: TranslationEngine.githubCopilot.displayName,
                statusCode: statusCode,
                responseData: data
            )
            DebugLogger.shared.logAPIError(
                sanitized,
                category: .translationCopilot,
                model: model,
                endpoint: baseURL
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
