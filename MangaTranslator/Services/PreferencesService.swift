import Foundation

final class PreferencesService: ObservableObject {
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-5"


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

    init() {
        let sourceLang = UserDefaults.standard.string(forKey: "sourceLanguage") ?? Language.ja.rawValue
        let targetLang = UserDefaults.standard.string(forKey: "targetLanguage") ?? Language.zhHant.rawValue
        let engine = UserDefaults.standard.string(forKey: "translationEngine") ?? "openai"
        let openAIM = UserDefaults.standard.string(forKey: "openAIModel") ?? Self.defaultOpenAIModel
        let openAIURL = UserDefaults.standard.string(forKey: "openAIBaseURL") ?? Self.defaultOpenAIBaseURL

        self.sourceLanguage = Language(rawValue: sourceLang) ?? .ja
        self.targetLanguage = Language(rawValue: targetLang) ?? .zhHant
        self.translationEngine = TranslationEngine(rawValue: engine) ?? .openAI
        self.openAIModel = openAIM
        self.openAIBaseURL = openAIURL
    }
}
