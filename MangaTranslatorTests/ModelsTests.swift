import Testing
@testable import MangaTranslator

@Suite("Models")
struct ModelsTests {

    @Test("Language.displayName returns correct display labels")
    func languageDisplayNameLabels() {
        #expect(Language.ja.displayName == "🇯🇵 Japanese")
        #expect(Language.en.displayName == "🇺🇸 English")
        #expect(Language.zhHant.displayName == "🇹🇼 Traditional Chinese")
    }

    @Test("Language.rawValue remains stable for persistence and routing")
    func languageRawValues() {
        #expect(Language.ja.rawValue == "ja")
        #expect(Language.en.rawValue == "en")
        #expect(Language.zhHant.rawValue == "zh-Hant")
    }
}
