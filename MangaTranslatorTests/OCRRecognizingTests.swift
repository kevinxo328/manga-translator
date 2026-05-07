import XCTest
import CoreGraphics
@testable import MangaTranslator

final class OCRRecognizingTests: XCTestCase {

    // MangaOCRService starts with nil recognizer (protocol type)
    func testMangaOCRServiceStartsWithNilRecognizer() async {
        let service = MangaOCRService()
        let recognizer = await service.recognizer
        XCTAssertNil(recognizer)
    }

    // MangaOCRService accepts any OCRRecognizing (protocol injection)
    func testMangaOCRServiceAcceptsOCRRecognizingProtocol() async {
        let service = MangaOCRService()
        await service.setRecognizer(MockOCRRecognizer())
        let recognizer = await service.recognizer
        XCTAssertNotNil(recognizer)
    }

    // resetRecognizer() sets internal recognizer to nil
    func testResetRecognizerSetsToNil() async {
        let service = MangaOCRService()
        await service.setRecognizer(MockOCRRecognizer())
        var recognizer = await service.recognizer
        XCTAssertNotNil(recognizer)

        await service.resetRecognizer()
        recognizer = await service.recognizer
        XCTAssertNil(recognizer)
    }
}

// MARK: - Mocks

private final class MockOCRRecognizer: @unchecked Sendable, OCRRecognizing {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        return ("mock", 1.0)
    }
}
