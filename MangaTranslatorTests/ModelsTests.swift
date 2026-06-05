import Testing
@testable import MangaTranslator

@Suite("Models")
struct ModelsTests {

    @Test("Language.displayName returns correct display labels")
    func languageDisplayNameLabels() {
        #expect(Language.en.displayName == "🇺🇸 English")
        #expect(Language.fr.displayName == "🇫🇷 French")
        #expect(Language.de.displayName == "🇩🇪 German")
        #expect(Language.id.displayName == "🇮🇩 Indonesian")
        #expect(Language.ja.displayName == "🇯🇵 Japanese")
        #expect(Language.ko.displayName == "🇰🇷 Korean")
        #expect(Language.ptBR.displayName == "🇧🇷 Portuguese (Brazil)")
        #expect(Language.zhHans.displayName == "🇨🇳 Simplified Chinese")
        #expect(Language.es.displayName == "🇪🇸 Spanish")
        #expect(Language.zhHant.displayName == "🇹🇼 Traditional Chinese")
        #expect(Language.vi.displayName == "🇻🇳 Vietnamese")
    }

    @Test("Language.rawValue remains stable for persistence and routing")
    func languageRawValues() {
        #expect(Language.en.rawValue == "en")
        #expect(Language.fr.rawValue == "fr")
        #expect(Language.de.rawValue == "de")
        #expect(Language.id.rawValue == "id")
        #expect(Language.ja.rawValue == "ja")
        #expect(Language.ko.rawValue == "ko")
        #expect(Language.ptBR.rawValue == "pt-BR")
        #expect(Language.zhHans.rawValue == "zh-Hans")
        #expect(Language.es.rawValue == "es")
        #expect(Language.zhHant.rawValue == "zh-Hant")
        #expect(Language.vi.rawValue == "vi")
    }

    @Test("Language.allCases contains every persisted language case in declaration order")
    func allLanguageCases() {
        #expect(Language.allCases == [
            .ja,
            .en,
            .zhHant,
            .fr,
            .de,
            .id,
            .ko,
            .ptBR,
            .zhHans,
            .es,
            .vi
        ])
    }

    @Test("Language.sourceLanguages exposes only OCR-supported source languages in A-Z order")
    func sourceLanguagesContents() {
        // zhHant is a target-only language; exposing it here would break
        // the source language pickers in SettingsView and ContentView.
        #expect(Language.sourceLanguages == [.en, .ja])
        #expect(!Language.sourceLanguages.contains(.zhHant))
    }

    @Test("Language.targetLanguages exposes supported targets in A-Z order")
    func targetLanguagesContents() {
        #expect(Language.targetLanguages == [
            .en,
            .fr,
            .de,
            .id,
            .ja,
            .ko,
            .ptBR,
            .zhHans,
            .es,
            .zhHant,
            .vi
        ])
    }

    @Test("BubbleCluster.isInverted defaults to false for legacy initializers")
    func bubbleClusterIsInvertedDefault() {
        let bubble = BubbleCluster(boundingBox: .zero, text: "test", observations: [])
        #expect(bubble.isInverted == false)
    }

    @Test("MangaOCRPageResult with nil textPixelMask round-trips correctly")
    func mangaOCRPageResultNilMask() {
        let result = MangaOCRPageResult(bubbles: [], textPixelMask: nil, lowConfidenceDetectionCount: 0)
        #expect(result.bubbles.isEmpty)
        #expect(result.textPixelMask == nil)
        #expect(result.lowConfidenceDetectionCount == 0)
    }
}
