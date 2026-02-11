import Foundation

final class PreferencesService: ObservableObject {
    @Published var sourceLanguage: Language {
        didSet { UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "sourceLanguage") }
    }

    @Published var targetLanguage: Language {
        didSet { UserDefaults.standard.set(targetLanguage.rawValue, forKey: "targetLanguage") }
    }

    @Published var translationEngine: TranslationEngine {
        didSet { UserDefaults.standard.set(translationEngine.rawValue, forKey: "translationEngine") }
    }

    @Published var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") }
    }

    init() {
        let sourceLang = UserDefaults.standard.string(forKey: "sourceLanguage") ?? Language.ja.rawValue
        let targetLang = UserDefaults.standard.string(forKey: "targetLanguage") ?? Language.zhHant.rawValue
        let engine = UserDefaults.standard.string(forKey: "translationEngine") ?? TranslationEngine.claude.rawValue
        let claudeM = UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-4-5-20250929"
        let openAIM = UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4o-mini"

        self.sourceLanguage = Language(rawValue: sourceLang) ?? .ja
        self.targetLanguage = Language(rawValue: targetLang) ?? .zhHant
        self.translationEngine = TranslationEngine(rawValue: engine) ?? .claude
        self.claudeModel = claudeM
        self.openAIModel = openAIM
    }
}
