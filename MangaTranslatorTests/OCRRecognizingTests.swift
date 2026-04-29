import XCTest
import CoreGraphics
@testable import MangaTranslator

final class OCRRecognizingTests: XCTestCase {

    // MangaOCRService starts with nil recognizer (protocol type)
    func testMangaOCRServiceStartsWithNilRecognizer() {
        let service = MangaOCRService()
        XCTAssertNil(service.recognizer)
    }

    // MangaOCRService accepts any OCRRecognizing (protocol injection)
    func testMangaOCRServiceAcceptsOCRRecognizingProtocol() {
        let service = MangaOCRService()
        service.recognizer = MockOCRRecognizer()
        XCTAssertNotNil(service.recognizer)
    }

    // resetRecognizer() sets internal recognizer to nil
    func testResetRecognizerSetsToNil() {
        let service = MangaOCRService()
        service.recognizer = MockOCRRecognizer()
        XCTAssertNotNil(service.recognizer)

        service.resetRecognizer()
        XCTAssertNil(service.recognizer)
    }
}

// MARK: - Mocks

private final class MockOCRRecognizer: OCRRecognizing {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        return ("mock", 1.0)
    }
}
