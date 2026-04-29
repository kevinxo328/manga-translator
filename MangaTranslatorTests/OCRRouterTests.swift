import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

@MainActor
final class OCRRouterTests: XCTestCase {

    // MARK: - Task 6.1: Routing decisions

    func testSiliconDownloadedEnabledCallsPaddleOCRFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: {
                factoryCalled = true
                return MockOCRRecognizer(name: "paddle")
            }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertTrue(factoryCalled, "PaddleOCR factory must be called when Silicon+downloaded+enabled")
    }

    func testSiliconNotDownloadedDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called when model is not downloaded")
    }

    func testSiliconDownloadedDisabledDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: false),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called when paddleocr is disabled")
    }

    func testUnsupportedCapabilityDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called on unsupported (Intel) device")
    }

    func testEnabledWithoutDownloadIsRejected() async {
        // isPaddleOCREnabled checks state == .downloaded first; .notDownloaded blocks activation.
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: true),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called when model is not downloaded, even if enabled flag is set")
    }

    // MARK: - Task 6.2: Strict-mode failure

    func testPaddleOCRFactoryFailureThrowsPaddleOCRError() async throws {
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { throw PaddleOCRError.inferenceFailed("test trigger") }
        )

        do {
            _ = try await router.processPage(image: NSImage(), sourceLanguage: .ja)
            XCTFail("Expected PaddleOCRError to be thrown")
        } catch let error as PaddleOCRError {
            XCTAssertEqual(error.code, "paddleocr.inference_failed")
        } catch {
            XCTFail("Expected PaddleOCRError, got \(type(of: error)): \(error)")
        }
    }

    func testPaddleOCRInferenceFailureDoesNotFallBackToMangaOCR() async {
        // When PaddleOCR is active and fails, MangaOCRService.recognizeAndCluster
        // must NOT be invoked with the MangaOCR recognizer. We verify by checking
        // that no MangaOCR-flavoured result is returned (error is propagated instead).
        let throwingRecognizer = ThrowingOCRRecognizer()
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { throwingRecognizer }
        )

        do {
            _ = try await router.processPage(image: NSImage(), sourceLanguage: .ja)
            XCTFail("Expected an error")
        } catch is PaddleOCRError {
            // Correct: PaddleOCRError was propagated, not a MangaOCR result.
        } catch {
            XCTFail("Expected PaddleOCRError, got \(error)")
        }
    }

    // MARK: - Task 6.2a: Stable error codes

    func testModelUnavailableCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.modelUnavailable.code, "paddleocr.model_unavailable")
    }

    func testInferenceFailedCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.inferenceFailed("any").code, "paddleocr.inference_failed")
    }

    func testDownloadFailedCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.downloadFailed("any").code, "paddleocr.download_failed")
    }

    func testVerifyFailedCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.verifyFailed.code, "paddleocr.verify_failed")
    }

    func testStorageUnavailableCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.storageUnavailable("x").code, "paddleocr.storage_unavailable")
    }

    func testOperationCancelledCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.operationCancelled.code, "paddleocr.operation_cancelled")
    }

    // MARK: - Task 6.2b: Error code / localization key independence

    func testErrorCodeIsNotTheLocalizationString() {
        // The stable error code must differ from the user-facing message.
        // This ensures code keys and localization keys are separate concerns.
        let cases: [PaddleOCRError] = [
            .modelUnavailable,
            .inferenceFailed("x"),
            .downloadFailed("x"),
            .verifyFailed,
            .storageUnavailable("x"),
            .operationCancelled,
        ]
        for error in cases {
            let code = error.code
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty,
                           "\(code): errorDescription must not be empty")
            XCTAssertNotEqual(code, description,
                              "\(code): error code must differ from user-facing localization string")
        }
    }

    // MARK: - Task 6.3: Reset tests

    func testResetPaddleOCRRecognizerClearsRecognizer() {
        let service = MangaOCRService()
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true)
        )

        service.recognizer = MockOCRRecognizer(name: "active")
        XCTAssertNotNil(service.recognizer)

        router.resetPaddleOCRRecognizer()
        XCTAssertNil(service.recognizer, "resetPaddleOCRRecognizer() must clear the active recognizer")
    }

    func testRecognizerResetsWhenPreferenceToggledViaResetMethod() {
        // Simulates the preference-toggle path: caller toggles preference then calls reset.
        let service = MangaOCRService()
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true)
        )

        service.recognizer = MockOCRRecognizer(name: "paddle-active")
        router.resetPaddleOCRRecognizer()
        XCTAssertNil(service.recognizer)
    }

    func testRecognizerResetsWhenModelDeletedViaResetMethod() {
        // Simulates the model-delete path: ModelDownloadService calls reset on the router.
        let service = MangaOCRService()
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true)
        )

        service.recognizer = MockOCRRecognizer(name: "paddle-active")
        router.resetPaddleOCRRecognizer()
        XCTAssertNil(service.recognizer, "Recognizer must be released after model deletion")
    }
}

// MARK: - Mock Types

private final class MockCapabilityChecker: DeviceCapabilityChecking {
    private let capability: PaddleOCRCapability
    init(_ capability: PaddleOCRCapability) { self.capability = capability }
    func checkPaddleOCRCapability() -> PaddleOCRCapability { capability }
}

private final class MockDownloadManager: ModelDownloadManaging {
    let state: ModelDownloadState
    private let enabled: Bool
    init(state: ModelDownloadState, enabled: Bool = false) {
        self.state = state
        self.enabled = enabled
    }
    var isPaddleOCREnabled: Bool { state == .downloaded && enabled }
}

private final class MockOCRRecognizer: OCRRecognizing {
    let name: String
    init(name: String = "mock") { self.name = name }
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        return (name, 1.0)
    }
}

private final class ThrowingOCRRecognizer: OCRRecognizing {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        throw PaddleOCRError.inferenceFailed("forced failure")
    }
}
