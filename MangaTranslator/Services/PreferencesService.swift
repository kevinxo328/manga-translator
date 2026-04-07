import Foundation

final class PreferencesService: ObservableObject {
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-5"
    static let defaultCopilotModel = "gpt-5-mini"


    @Published var sourceLanguage: Language {
        didSet { UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "sourceLanguage") }
    }

    @Published var targetLanguage: Language {
        didSet { UserDefaults.standard.set(targetLanguage.rawValue, forKey: "targetLanguage") }
    }

    @Published var translationEngine: TranslationEngine {
        didSet { UserDefaults.standard.set(translationEngine.rawValue, forKey: "translationEngine") }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") }
    }

    @Published var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: "openAIBaseURL") }
    }

    @Published var copilotModel: String {
        didSet { UserDefaults.standard.set(copilotModel, forKey: "copilotModel") }
    }

    @Published var showPathBar: Bool {
        didSet { UserDefaults.standard.set(showPathBar, forKey: "showPathBar") }
    }

    init() {
        let sourceLang = UserDefaults.standard.string(forKey: "sourceLanguage") ?? Language.ja.rawValue
        let targetLang = UserDefaults.standard.string(forKey: "targetLanguage") ?? Language.zhHant.rawValue
        let engine = UserDefaults.standard.string(forKey: "translationEngine") ?? "openai"
        let openAIM = UserDefaults.standard.string(forKey: "openAIModel") ?? Self.defaultOpenAIModel
        let openAIURL = UserDefaults.standard.string(forKey: "openAIBaseURL") ?? Self.defaultOpenAIBaseURL
        let copilotM = UserDefaults.standard.string(forKey: "copilotModel") ?? Self.defaultCopilotModel
        let showP = UserDefaults.standard.object(forKey: "showPathBar") as? Bool ?? true

        self.sourceLanguage = Language(rawValue: sourceLang) ?? .ja
        self.targetLanguage = Language(rawValue: targetLang) ?? .zhHant
        self.translationEngine = TranslationEngine(rawValue: engine) ?? .openAI
        self.openAIModel = openAIM
        self.openAIBaseURL = openAIURL
        self.copilotModel = copilotM
        self.showPathBar = showP
    }
}
