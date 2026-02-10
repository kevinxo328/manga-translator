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

    init() {
        let sourceLang = UserDefaults.standard.string(forKey: "sourceLanguage") ?? Language.ja.rawValue
        let targetLang = UserDefaults.standard.string(forKey: "targetLanguage") ?? Language.zhHant.rawValue
        let engine = UserDefaults.standard.string(forKey: "translationEngine") ?? TranslationEngine.claude.rawValue

        self.sourceLanguage = Language(rawValue: sourceLang) ?? .ja
        self.targetLanguage = Language(rawValue: targetLang) ?? .zhHant
        self.translationEngine = TranslationEngine(rawValue: engine) ?? .claude
    }
}
