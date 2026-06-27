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
    let apiErrorRetryClassifier: @Sendable (SanitizedAPIError) -> Bool
    let debugLogger: DebugLogger

    /// Both translate paths share the same retry budget: one retry with
    /// backoff, applied to API/network failures and parse failures alike.
    private let maxAttempts = 2
    private var endpointDescription: String { endpoint.absoluteString }

    // 500ms backoff * 2^(attempt-1); only one retry per design.
    private static func backoffNanos(afterAttempt attempt: Int) -> UInt64 {
        500_000_000 * UInt64(1 << (attempt - 1))
    }

    /// Shared sampling temperature for all LLM translation requests.
    static let temperature: Double = 0.3

    /// Loose upper bound on response tokens: a base for JSON scaffolding and
    /// the optional detected_terms block, plus per-page and per-bubble
    /// allowances. The per-bubble allowance is sized for token-heavy target
    /// languages (CJK tokenizes at ~1-2 tokens per character) so a legitimate
    /// translation is never truncated; the cap only exists to bound the cost
    /// of runaway repetition loops.
    ///
    /// Deliberately unclamped: large batches can exceed the output limit of
    /// some models (e.g. 16,384), where certain providers reject the request
    /// with HTTP 400 instead of clamping. We accept that trade-off to avoid
    /// ever truncating output on high-limit models; revisit if a capped model
    /// needs to be supported.
    static func estimatedMaxTokens(bubbleCount: Int, pageCount: Int) -> Int {
        4096 + 512 * pageCount + 1024 * bubbleCount
    }

    init(
        endpoint: URL,
        model: String,
        extraHeaders: [String: String] = [:],
        provider: APIErrorSanitizer.Provider,
        providerDisplayName: String,
        category: DebugLogCategory,
        urlSession: URLSession,
        apiErrorRetryClassifier: @escaping @Sendable (SanitizedAPIError) -> Bool = { _ in true },
        debugLogger: DebugLogger = .shared
    ) {
        self.endpoint = endpoint
        self.model = model
        self.extraHeaders = extraHeaders
        self.provider = provider
        self.providerDisplayName = providerDisplayName
        self.category = category
        self.urlSession = urlSession
        self.apiErrorRetryClassifier = apiErrorRetryClassifier
        self.debugLogger = debugLogger
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext,
        authToken: String
    ) async throws -> TranslationOutput {
        debugLogger.logAPIDiagnostic(
            "Translation started: bubbles=\(bubbles.count) \(source.rawValue)→\(target.rawValue)",
            category: category, model: model, endpoint: endpointDescription
        )

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target, context: context)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        var lastResponseText: String?
        var lastError: Error?
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let responseText = try await callAPI(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    authToken: authToken,
                    maxTokens: Self.estimatedMaxTokens(bubbleCount: bubbles.count, pageCount: 1)
                )
                do {
                    let (parsed, detected) = try LLMResponseParser.parse(responseText, bubbles: bubbles)
                    debugLogger.logAPIDiagnostic(
                        "Translation completed: bubbles=\(parsed.count)",
                        category: category, statusCode: 200, model: model
                    )
                    return TranslationOutput(bubbles: parsed, detectedTerms: detected)
                } catch {
                    lastResponseText = responseText
                    lastError = error
                    // Log error type and response length only; response content
                    // may carry user text and stays out of the logs.
                    debugLogger.log(
                        "Translation attempt \(attempt)/\(maxAttempts) parse failed: \(type(of: error)), response length \(responseText.count)",
                        level: .warning, category: category
                    )
                }
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch is CancellationError {
                throw CancellationError()
            } catch TranslationError.apiError(let error) where !apiErrorRetryClassifier(error) {
                throw TranslationError.apiError(error)
            } catch {
                lastError = error
                debugLogger.log(
                    "Translation attempt \(attempt)/\(maxAttempts) API call failed",
                    level: .warning, category: category
                )
            }
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: Self.backoffNanos(afterAttempt: attempt))
            }
        }

        // Parse failures degrade to line-based fallback so the page still
        // renders; API/network failures have nothing to fall back on.
        if let responseText = lastResponseText {
            debugLogger.log("Translation response parse failed after \(maxAttempts) attempts, using fallback", level: .warning, category: category)
            let (fallback, _) = LLMResponseParser.fallbackParse(responseText, bubbles: bubbles)
            return TranslationOutput(bubbles: fallback, detectedTerms: [])
        }
        throw lastError ?? TranslationError.invalidResponse
    }

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext,
        authToken: String
    ) async throws -> [BatchPageOutput] {
        debugLogger.logAPIDiagnostic(
            "translateBatch started: pages=\(pageInputs.count) \(source.rawValue)→\(target.rawValue)",
            category: category, model: model, endpoint: endpointDescription
        )

        let systemPrompt = LLMPrompt.multiPageSystemPrompt(from: source, to: target, context: priorContext)
        let userPrompt = LLMPrompt.multiPageUserPrompt(pageInputs: pageInputs)

        var lastError: Error?
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let responseText = try await callAPI(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    authToken: authToken,
                    maxTokens: Self.estimatedMaxTokens(
                        bubbleCount: pageInputs.reduce(0) { $0 + $1.bubbles.count },
                        pageCount: pageInputs.count
                    )
                )
                let outputs = try LLMResponseParser.parseMultiPage(responseText, pageInputs: pageInputs)
                debugLogger.logAPIDiagnostic(
                    "translateBatch completed: pages=\(outputs.count)",
                    category: category, statusCode: 200, model: model
                )
                return outputs
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch is CancellationError {
                throw CancellationError()
            } catch TranslationError.apiError(let error) where !apiErrorRetryClassifier(error) {
                throw TranslationError.apiError(error)
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: Self.backoffNanos(afterAttempt: attempt))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? TranslationError.invalidResponse
    }

    func callAPI(systemPrompt: String, userPrompt: String, authToken: String, maxTokens: Int) async throws -> String {
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
            "temperature": Self.temperature,
            "max_tokens": maxTokens
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
            debugLogger.logAPIError(
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
