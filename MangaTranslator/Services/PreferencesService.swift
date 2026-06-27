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
