import Testing
@testable import MangaTranslator

@Suite("Models")
struct ModelsTests {

    @Test("Language.displayName returns correct short codes")
    func languageDisplayNameShortCodes() {
        #expect(Language.ja.displayName == "JA")
        #expect(Language.en.displayName == "EN")
        #expect(Language.zhHant.displayName == "ZH-TW")
    }
}
