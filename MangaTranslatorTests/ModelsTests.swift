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

    @Test("Language.sourceLanguages exposes only OCR-supported source languages: Japanese first, then English")
    func sourceLanguagesContents() {
        // zhHant is a target-only language; exposing it here would break
        // the source language pickers in SettingsView and ContentView.
        #expect(Language.sourceLanguages.count == 2)
        #expect(Language.sourceLanguages[0] == .ja)
        #expect(Language.sourceLanguages[1] == .en)
        #expect(!Language.sourceLanguages.contains(.zhHant))
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
