import XCTest
@testable import MangaTranslator

final class VisionOCRServiceTests: XCTestCase {

    func testDefaultUsesLanguageCorrection() {
        let service = VisionOCRService()
        XCTAssertTrue(service.usesLanguageCorrection,
                      "Language correction should be enabled by default to match Preview quality")
    }

    func testDefaultRecognitionLanguagesIncludeEnglish() {
        let service = VisionOCRService()
        XCTAssertTrue(service.recognitionLanguages.contains("en-US"),
                      "English should be included for mixed JP/EN manga content")
    }

    func testDefaultRecognitionLanguagesPrioritizesJapanese() {
        let service = VisionOCRService()
        XCTAssertEqual(service.recognitionLanguages.first, "ja-JP",
                       "Japanese should be the primary language")
    }

    func testRecognitionLanguagesRespectSourceLanguage() {
        let service = VisionOCRService()
        let languages = service.recognitionLanguages(for: .zhHant)
        XCTAssertEqual(languages.first, Locale.Language(identifier: "zh-Hant"),
                       "Source language should be first in the list")
        XCTAssertTrue(languages.contains(Locale.Language(identifier: "en-US")),
                      "English fallback should always be present")
    }

    func testLanguageCorrectionCanBeDisabled() {
        var service = VisionOCRService()
        service.usesLanguageCorrection = false
        XCTAssertFalse(service.usesLanguageCorrection)
    }

    // Small manga text (furigana, sound effects) needs low threshold
    func testMinimumTextHeightFractionIsLow() {
        let service = VisionOCRService()
        XCTAssertLessThanOrEqual(service.minimumTextHeightFraction, 0.01,
                                  "Default 3.125% filters out small manga text; must be ≤1%")
    }

    func testMinimumTextHeightFractionCanBeAdjusted() {
        var service = VisionOCRService()
        service.minimumTextHeightFraction = 0.005
        XCTAssertEqual(service.minimumTextHeightFraction, 0.005)
    }
}
