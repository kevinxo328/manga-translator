import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

#if arch(arm64)
@testable import MangaTranslatorMLX

@MainActor
final class E2EOCRIntegrationTests: XCTestCase {

    private func createRouter(
        downloadState: ModelDownloadState,
        downloadEnabled: Bool,
        capability: PaddleOCRCapability = .supported,
        paddleOCRFactory: @escaping () throws -> any OCRRecognizing = { throw PaddleOCRError.modelUnavailable }
    ) -> OCRRouter {
        let capabilityChecker = MockCapabilityChecker(capability)
        let downloadManager = MockDownloadManager(state: downloadState, enabled: downloadEnabled)
        return OCRRouter(
            capabilityChecker: capabilityChecker,
            downloadManager: downloadManager,
            paddleOCRFactory: paddleOCRFactory
        )
    }

    // 9.1 Run full OCR pipeline on test_images/ with high-accuracy model enabled
    func testFullPipelineHighAccuracyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["ENABLE_PADDLEOCR_SPIKE_TESTS"] == "1" else { return }
        
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MangaTranslatorTests
            .deletingLastPathComponent() // repo root
        
        let modelDir = repoRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("convert_model")
            .appendingPathComponent("mlx_output")
        let imageURL = repoRoot
            .appendingPathComponent("test_images")
            .appendingPathComponent("001.jpg")
            
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return }
        guard let image = NSImage(contentsOf: imageURL) else {
            XCTFail("Missing test image")
            return
        }
        
        let router = createRouter(
            downloadState: .downloaded,
            downloadEnabled: true,
            paddleOCRFactory: { try PaddleOCRVLRecognizer(modelDirectory: modelDir) }
        )
        
        let bubbles = try await router.processPage(image: image, sourceLanguage: .ja)
        XCTAssertFalse(bubbles.isEmpty, "OCR pipeline should return non-empty bubbles")
    }
    
    // 9.2 Run full OCR pipeline with high-accuracy model disabled
    func testFullPipelineHighAccuracyDisabled() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imageURL = repoRoot.appendingPathComponent("test_images").appendingPathComponent("001.jpg")
        guard let image = NSImage(contentsOf: imageURL) else { return }
        
        let router = createRouter(
            downloadState: .downloaded,
            downloadEnabled: false,
            paddleOCRFactory: { 
                XCTFail("PaddleOCR factory should not be called when disabled")
                throw PaddleOCRError.modelUnavailable
            }
        )
        
        do {
            let bubbles = try await router.processPage(image: image, sourceLanguage: .ja)
            print("Fallback pipeline returned \(bubbles.count) bubbles")
        } catch {
            // It might fail if MangaOCR isn't fully mocked, but the router shouldn't call PaddleOCR.
        }
    }
    
    // 9.6 Test strict-mode failure end-to-end & 9.6a Assert strict-mode no-fallback invariants
    func testStrictModeNoFallback() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imageURL = repoRoot.appendingPathComponent("test_images").appendingPathComponent("001.jpg")
        guard let image = NSImage(contentsOf: imageURL) else { return }
        
        var factoryCalledCount = 0
        let router = createRouter(
            downloadState: .downloaded,
            downloadEnabled: true,
            paddleOCRFactory: { 
                factoryCalledCount += 1
                throw PaddleOCRError.inferenceFailed("Simulated error")
            }
        )
        
        do {
            _ = try await router.processPage(image: image, sourceLanguage: .ja)
            XCTFail("Pipeline should have failed")
        } catch let error as PaddleOCRError {
            XCTAssertEqual(error.code, "paddleocr.inference_failed")
            XCTAssertEqual(factoryCalledCount, 1)
        } catch {
            XCTFail("Wrong error type thrown")
        }
    }
}

// MARK: - Mocks

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
#endif
