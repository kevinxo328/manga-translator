import Testing
import Foundation
import AppKit
@testable import MangaTranslator

#if arch(arm64)
@testable import MangaTranslatorMLX
#endif

// MARK: - Test helpers

private func makeSolidCGImage(width: Int, height: Int, color: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> CGImage? {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
    for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
        pixelData[i]     = color.0
        pixelData[i + 1] = color.1
        pixelData[i + 2] = color.2
        pixelData[i + 3] = 255
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &pixelData,
        width: width, height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    return context.makeImage()
}

#if arch(arm64)
// MARK: - Mock engine

private final class MockOCREngine: PaddleOCRInferencing {
    var result: (text: String, confidence: Float) = ("テスト", 0.95)
    var shouldThrow = false
    var callCount = 0

    func infer(image: CGImage) throws -> (text: String, confidence: Float) {
        callCount += 1
        if shouldThrow { throw PaddleOCRError.inferenceFailed("mock error") }
        return result
    }
}

// MARK: - Tests

@Suite("PaddleOCRVLRecognizer")
@MainActor
struct PaddleOCRVLRecognizerTests {

    // MARK: - Task 33: Successful inference

    @Test("Successful inference returns structured output without crash")
    func successfulInference() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else {
            Issue.record("Could not create test image")
            return
        }
        let region = CGRect(x: 0, y: 0, width: 100, height: 50)
        let (text, confidence) = try recognizer.recognizeText(in: image, region: region)

        #expect(text == "テスト")
        #expect(confidence == 0.95)
    }

    @Test("Model directory missing before inference throws PaddleOCRError.modelUnavailable")
    func missingModelDirectoryThrowsDescriptiveError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Do NOT create the directory
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let region = CGRect(x: 0, y: 0, width: 100, height: 50)

        #expect(throws: PaddleOCRError.modelUnavailable) {
            _ = try recognizer.recognizeText(in: image, region: region)
        }
    }

    // MARK: - Task 34: Boundary tests

    @Test("Region exceeding image bounds is clamped — no crash")
    func regionExceedsBoundsIsClamped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        // Region extends beyond image bounds
        let region = CGRect(x: 50, y: 25, width: 200, height: 200)
        let result = try recognizer.recognizeText(in: image, region: region)

        #expect(result.text == "テスト")
    }

    @Test("Region with zero width returns empty string without crash")
    func zeroWidthRegionReturnsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let region = CGRect(x: 10, y: 10, width: 0, height: 30)
        let (text, confidence) = try recognizer.recognizeText(in: image, region: region)

        #expect(text.isEmpty || confidence == 0)
    }

    @Test("Region with zero height returns empty string without crash")
    func zeroHeightRegionReturnsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let region = CGRect(x: 10, y: 10, width: 30, height: 0)
        let (text, confidence) = try recognizer.recognizeText(in: image, region: region)

        #expect(text.isEmpty || confidence == 0)
    }

    @Test("All-white input image returns result without crashing")
    func allWhiteInputNoCrash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("", 0)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50, color: (255, 255, 255)) else { return }
        let region = CGRect(x: 0, y: 0, width: 100, height: 50)
        let result = try recognizer.recognizeText(in: image, region: region)

        // Should not crash; result may be empty
        #expect(result.text.isEmpty || result.confidence >= 0)
    }

    @Test("All-black input image returns result without crashing")
    func allBlackInputNoCrash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("", 0)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50, color: (0, 0, 0)) else { return }
        let region = CGRect(x: 0, y: 0, width: 100, height: 50)
        let result = try recognizer.recognizeText(in: image, region: region)

        #expect(result.text.isEmpty || result.confidence >= 0)
    }

    @Test("4K+ input image completes without out-of-memory crash")
    func largeInputImageNoCrash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 3840, height: 2160) else { return }
        let region = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let result = try recognizer.recognizeText(in: image, region: region)

        #expect(result.confidence >= 0)
    }

    // MARK: - Task 35: Memory pressure

    @Test("Model is released after NSApplication.didReceiveMemoryWarningNotification")
    func memoryPressureReleasesModel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 50, height: 50) else { return }
        let region = CGRect(x: 0, y: 0, width: 50, height: 50)

        // First inference loads the engine
        _ = try recognizer.recognizeText(in: image, region: region)
        #expect(mockEngine.callCount == 1)

        // Simulate memory pressure
        NotificationCenter.default.post(name: NSApplication.didReceiveMemoryWarningNotification, object: nil)

        // After memory pressure, engine should be nil internally
        // We verify by checking that the next inference re-loads (callCount resets to a new instance)
        // We use a factory that counts creations
        var factoryCallCount = 0
        let recognizer2 = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in
            factoryCallCount += 1
            return MockOCREngine()
        }
        _ = try recognizer2.recognizeText(in: image, region: region)
        NotificationCenter.default.post(name: NSApplication.didReceiveMemoryWarningNotification, object: nil)
        _ = try recognizer2.recognizeText(in: image, region: region)

        // Factory should have been called twice (once before and once after memory pressure)
        #expect(factoryCallCount == 2)
    }

    @Test("Inference after memory pressure reloads engine and succeeds")
    func inferenceAfterMemoryPressureSucceeds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var loadCount = 0
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in
            loadCount += 1
            return MockOCREngine()
        }

        guard let image = makeSolidCGImage(width: 50, height: 50) else { return }
        let region = CGRect(x: 0, y: 0, width: 50, height: 50)

        _ = try recognizer.recognizeText(in: image, region: region)
        #expect(loadCount == 1)

        NotificationCenter.default.post(name: NSApplication.didReceiveMemoryWarningNotification, object: nil)

        let (text, _) = try recognizer.recognizeText(in: image, region: region)
        #expect(loadCount == 2)
        #expect(text == "テスト")
    }

    // MARK: - Task 36: Explicit unload hook

    @Test("unload() releases model resources deterministically")
    func explicitUnloadReleasesResources() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var loadCount = 0
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in
            loadCount += 1
            return MockOCREngine()
        }

        guard let image = makeSolidCGImage(width: 50, height: 50) else { return }
        let region = CGRect(x: 0, y: 0, width: 50, height: 50)

        _ = try recognizer.recognizeText(in: image, region: region)
        #expect(loadCount == 1)

        recognizer.unload()

        _ = try recognizer.recognizeText(in: image, region: region)
        #expect(loadCount == 2, "unload() should force a reload on next inference")
    }

    @Test("unload() succeeds without crash when called before any inference")
    func unloadBeforeInferenceNoCrash() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }
        recognizer.unload()
        // Should not crash
        #expect(Bool(true))
    }
}
#endif
