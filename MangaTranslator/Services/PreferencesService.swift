import Foundation

final class PreferencesService: ObservableObject {
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-5"
    static let defaultCopilotModel = "auto"

    private let defaults: UserDefaults

    @Published var sourceLanguage: Language {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: "sourceLanguage") }
    }

    @Published var targetLanguage: Language {
        didSet { defaults.set(targetLanguage.rawValue, forKey: "targetLanguage") }
    }

    @Published var translationEngine: TranslationEngine {
        didSet { defaults.set(translationEngine.rawValue, forKey: "translationEngine") }
    }

    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: "openAIModel") }
    }

    @Published var openAIBaseURL: String {
        didSet {
            guard (try? BaseURLValidator.validate(openAIBaseURL)) != nil else { return }
            defaults.set(openAIBaseURL, forKey: "openAIBaseURL")
        }
    }

    @Published var copilotModel: String {
        didSet { defaults.set(copilotModel, forKey: "copilotModel") }
    }

    @Published var showPathBar: Bool {
        didSet { defaults.set(showPathBar, forKey: "showPathBar") }
    }

    // In-memory only: drives Settings tab deep-linking. Never persisted to UserDefaults.
    // Supported values: "apiKeys", "preferences", "debug", "about", "glossary".
    // Resets to "apiKeys" on every fresh app launch.
    @Published var activeTabIdentifier: String = "apiKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let sourceLang = defaults.string(forKey: "sourceLanguage") ?? Language.ja.rawValue
        let targetLang = defaults.string(forKey: "targetLanguage") ?? Language.zhHant.rawValue
        let engine = defaults.string(forKey: "translationEngine") ?? "openai"
        let openAIM = defaults.string(forKey: "openAIModel") ?? Self.defaultOpenAIModel
        let openAIURL = defaults.string(forKey: "openAIBaseURL") ?? Self.defaultOpenAIBaseURL
        let copilotM = defaults.string(forKey: "copilotModel") ?? Self.defaultCopilotModel
        let showP = defaults.object(forKey: "showPathBar") as? Bool ?? true

        self.sourceLanguage = Language(rawValue: sourceLang).flatMap { Language.sourceLanguages.contains($0) ? $0 : nil } ?? .ja
        self.targetLanguage = Language(rawValue: targetLang) ?? .zhHant
        self.translationEngine = TranslationEngine(rawValue: engine) ?? .openAI
        self.openAIModel = openAIM
        self.openAIBaseURL = openAIURL
        self.copilotModel = copilotM
        self.showPathBar = showP
    }
}

extension TranslationEngineRegistry {
    static func makeService(
        for engine: TranslationEngine,
        preferences: PreferencesService,
        keychainService: KeychainService
    ) -> any TranslationService {
        switch engine {
        case .deepL:
            DeepLTranslationService(keychainService: keychainService)
        case .google:
            GoogleTranslationService(keychainService: keychainService)
        case .openAI:
            OpenAITranslationService(
                model: preferences.openAIModel,
                baseURL: preferences.openAIBaseURL,
                keychainService: keychainService
            )
        case .chatGPTPlan:
            ChatGPTPlanTranslationService()
        case .githubCopilot:
            CopilotTranslationService(model: preferences.copilotModel)
        }
    }
}

struct ChatGPTPlanTranslationService: TranslationService {
    let engine = TranslationEngine.chatGPTPlan
    private let account: ChatGPTPlanAccountService
    private let urlSession: URLSession
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    private static let unsupportedStructuredOutputModelsKey = "chatGPTPlan.unsupportedStructuredOutputModels"
    private static let unsupportedStructuredOutputLifetime: TimeInterval = 7 * 24 * 60 * 60

    init(
        account: ChatGPTPlanAccountService = ChatGPTPlanAccountService(),
        urlSession: URLSession = .shared,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.urlSession = urlSession
        self.defaults = defaults
        self.now = now
    }

    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        let text = try await responseText(
            systemPrompt: LLMPrompt.systemPrompt(from: source, to: target, context: context),
            userPrompt: LLMPrompt.userPrompt(bubbles: bubbles)
        )
        let (translated, detectedTerms) = try LLMResponseParser.parse(text, bubbles: bubbles)
        return TranslationOutput(bubbles: translated, detectedTerms: detectedTerms)
    }

    func translateBatch(pageInputs: [BatchPageInput], from source: Language, to target: Language, priorContext: TranslationContext) async throws -> [BatchPageOutput] {
        guard let session = await account.session() else {
            throw TranslationError.chatGPTPlanNotConnected
        }
        guard let model = session.selectedModel, !model.isEmpty else {
            throw TranslationError.chatGPTPlanModelNotSelected
        }
        let systemPrompt = LLMPrompt.multiPageSystemPrompt(from: source, to: target, context: priorContext)
        let userPrompt = LLMPrompt.multiPageUserPrompt(pageInputs: pageInputs)
        let useStructuredOutput = !hasUnsupportedStructuredOutput(model: model)
        let text: String
        do {
            text = try await responseText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                structuredOutput: useStructuredOutput
            )
        } catch is ChatGPTPlanStructuredOutputUnsupportedError where useStructuredOutput {
            rememberUnsupportedStructuredOutput(model: model)
            DebugLogger.shared.logAPIDiagnostic(
                "ChatGPT Plan structured output unsupported; retrying compatible format",
                category: .translationOpenAI,
                model: model,
                endpoint: "https://api.openai.com/v1/responses"
            )
            text = try await responseText(systemPrompt: systemPrompt, userPrompt: userPrompt, structuredOutput: false)
        }
        return try LLMResponseParser.parseMultiPage(text, pageInputs: pageInputs)
    }

    private func responseText(systemPrompt: String, userPrompt: String, structuredOutput: Bool = false) async throws -> String {
        guard let session = await account.session() else {
            throw TranslationError.chatGPTPlanNotConnected
        }
        guard let model = session.selectedModel, !model.isEmpty else {
            throw TranslationError.chatGPTPlanModelNotSelected
        }
        let accessToken = try await account.validAccessToken()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var requestBody: [String: Any] = [
            "model": model,
            "instructions": systemPrompt,
            "input": [["role": "user", "content": userPrompt]],
            "store": false,
            "stream": true
        ]
        if structuredOutput {
            requestBody["text"] = ["format": Self.multiPageStructuredOutputFormat]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if structuredOutput, Self.isStructuredOutputUnsupported(responseData: data) {
                throw ChatGPTPlanStructuredOutputUnsupportedError()
            }
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .openAI,
                providerDisplayName: engine.displayName,
                statusCode: statusCode,
                responseData: data
            )
            DebugLogger.shared.logAPIError(sanitized, category: .translationOpenAI, model: model, endpoint: "https://api.openai.com/v1/responses")
            throw TranslationError.apiError(sanitized)
        }
        do {
            return try await ChatGPTPlanSSEDecoder.responseText(from: bytes)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw urlError
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error)
        }
    }

    private func hasUnsupportedStructuredOutput(model: String) -> Bool {
        var records = defaults.dictionary(forKey: Self.unsupportedStructuredOutputModelsKey) as? [String: Double] ?? [:]
        let currentTime = now().timeIntervalSince1970
        records = records.filter { $0.value > currentTime }
        defaults.set(records, forKey: Self.unsupportedStructuredOutputModelsKey)
        return records[model] != nil
    }

    private func rememberUnsupportedStructuredOutput(model: String) {
        var records = defaults.dictionary(forKey: Self.unsupportedStructuredOutputModelsKey) as? [String: Double] ?? [:]
        records[model] = now().addingTimeInterval(Self.unsupportedStructuredOutputLifetime).timeIntervalSince1970
        defaults.set(records, forKey: Self.unsupportedStructuredOutputModelsKey)
    }

    private static func isStructuredOutputUnsupported(responseData: Data) -> Bool {
        guard let body = String(data: responseData, encoding: .utf8)?.lowercased() else { return false }
        let identifiesStructuredOutput = body.contains("structured output")
            || body.contains("structured_output")
            || body.contains("json_schema")
        let identifiesUnsupportedCapability = body.contains("unsupported")
            || body.contains("not supported")
            || body.contains("does not support")
        return identifiesStructuredOutput && identifiesUnsupportedCapability
    }

    private static let multiPageStructuredOutputFormat: [String: Any] = [
        "type": "json_schema",
        "name": "manga_translation_batch",
        "strict": true,
        "schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["pages"],
            "properties": [
                "pages": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["page_id", "bubbles", "detected_terms"],
                        "properties": [
                            "page_id": ["type": "string"],
                            "bubbles": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "additionalProperties": false,
                                    "required": ["index", "translation"],
                                    "properties": [
                                        "index": ["type": "integer"],
                                        "translation": ["type": "string"]
                                    ]
                                ]
                            ],
                            "detected_terms": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "additionalProperties": false,
                                    "required": ["source", "target"],
                                    "properties": [
                                        "source": ["type": "string"],
                                        "target": ["type": "string"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ]
}

private struct ChatGPTPlanStructuredOutputUnsupportedError: Error {}

private enum ChatGPTPlanSSEDecoder {
    private struct Event: Decodable {
        struct ProviderError: Decodable {
            let code: String?
            let message: String?
        }

        struct Response: Decodable {
            let error: ProviderError?
        }

        let type: String
        let delta: String?
        let error: ProviderError?
        let response: Response?
    }

    static func responseText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var text = ""
        var completed = false

        func consume(_ payload: String) throws {
            guard !payload.isEmpty else { return }
            let event: Event
            do {
                event = try JSONDecoder().decode(Event.self, from: Data(payload.utf8))
            } catch {
                throw TranslationError.invalidResponse
            }
            switch event.type {
            case "response.output_text.delta":
                guard let delta = event.delta else { throw TranslationError.invalidResponse }
                text += delta
            case "response.completed":
                completed = true
            case "response.failed", "response.incomplete", "error":
                throw providerError(from: event, payload: payload)
            default:
                break
            }
        }
        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                try consume(String(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)))
            }
        }
        guard completed, !text.isEmpty else { throw TranslationError.invalidResponse }
        return text
    }

    private static func providerError(from event: Event, payload: String) -> TranslationError {
        let detail = event.error ?? event.response?.error
        let sanitized = SanitizedAPIError(
            provider: TranslationEngine.chatGPTPlan.displayName,
            statusCode: 200,
            code: detail?.code,
            message: detail?.message.flatMap(APIErrorSanitizer.redact)
        )
        if sanitized.code != nil || sanitized.message != nil { return .apiError(sanitized) }
        return .apiError(APIErrorSanitizer.sanitize(
            provider: .openAI,
            providerDisplayName: TranslationEngine.chatGPTPlan.displayName,
            statusCode: 200,
            responseData: Data(payload.utf8)
        ))
    }
}
