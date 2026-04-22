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
}
