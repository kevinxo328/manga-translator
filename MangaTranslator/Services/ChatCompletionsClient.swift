import Foundation

/// Shared chat/completions pipeline for LLM-backed translation services
/// (OpenAI-compatible and GitHub Copilot). Owns prompt assembly, the retry
/// skeletons, response parsing, and sanitized error logging. The owning
/// service stays responsible for authentication and endpoint configuration,
/// including any provider-specific sanitization of `endpoint` and `model`.
struct ChatCompletionsClient {
    let endpoint: URL
    let model: String
    let extraHeaders: [String: String]
    let provider: APIErrorSanitizer.Provider
    let providerDisplayName: String
    let category: DebugLogCategory
    let urlSession: URLSession

    private let maxRetries = 2
    private var endpointDescription: String { endpoint.absoluteString }

    init(
        endpoint: URL,
        model: String,
        extraHeaders: [String: String] = [:],
        provider: APIErrorSanitizer.Provider,
        providerDisplayName: String,
        category: DebugLogCategory,
        urlSession: URLSession
    ) {
        self.endpoint = endpoint
        self.model = model
        self.extraHeaders = extraHeaders
        self.provider = provider
        self.providerDisplayName = providerDisplayName
        self.category = category
        self.urlSession = urlSession
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext,
        authToken: String
    ) async throws -> TranslationOutput {
        DebugLogger.shared.logAPIDiagnostic(
            "Translation started: bubbles=\(bubbles.count) \(source.rawValue)→\(target.rawValue)",
            category: category, model: model, endpoint: endpointDescription
        )

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target, context: context)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        for attempt in 0...maxRetries {
            let responseText = try await callAPI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                authToken: authToken
            )

            if let (parsed, detected) = try? LLMResponseParser.parse(responseText, bubbles: bubbles) {
                DebugLogger.shared.logAPIDiagnostic(
                    "Translation completed: bubbles=\(parsed.count)",
                    category: category, statusCode: 200, model: model
                )
                return TranslationOutput(bubbles: parsed, detectedTerms: detected)
            }

            if attempt == maxRetries {
                DebugLogger.shared.log("Translation response parse failed after \(maxRetries + 1) attempts, using fallback", level: .warning, category: category)
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
        priorContext: TranslationContext,
        authToken: String
    ) async throws -> [BatchPageOutput] {
        DebugLogger.shared.logAPIDiagnostic(
            "translateBatch started: pages=\(pageInputs.count) \(source.rawValue)→\(target.rawValue)",
            category: category, model: model, endpoint: endpointDescription
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
                    authToken: authToken
                )
                let outputs = try LLMResponseParser.parseMultiPage(responseText, pageInputs: pageInputs)
                DebugLogger.shared.logAPIDiagnostic(
                    "translateBatch completed: pages=\(outputs.count)",
                    category: category, statusCode: 200, model: model
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

    func callAPI(systemPrompt: String, userPrompt: String, authToken: String) async throws -> String {
        let url = endpoint.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let sanitized = APIErrorSanitizer.sanitize(
                provider: provider,
                providerDisplayName: providerDisplayName,
                statusCode: statusCode,
                responseData: data
            )
            DebugLogger.shared.logAPIError(
                sanitized,
                category: category,
                model: model,
                endpoint: endpointDescription
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
