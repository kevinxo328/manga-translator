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

private func makeModelDirectoryWithWeights() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("fake-safetensors".utf8).write(to: directory.appendingPathComponent("model.safetensors"))
    return directory
}

private func makeModelDirectoryWithRuntimeArtifacts() throws -> URL {
    let directory = try makeModelDirectoryWithWeights()
    try Data("{\"vision_config\":{},\"text_config\":{}}".utf8).write(to: directory.appendingPathComponent("config.json"))
    try Data("{\"max_new_tokens\":1024}".utf8).write(to: directory.appendingPathComponent("generation_config.json"))
    try Data("{\"version\":\"1.0\",\"truncation\":null,\"padding\":null}".utf8).write(to: directory.appendingPathComponent("tokenizer_config.json"))
    try Data("{\"unk_token\":\"<unk>\"}".utf8).write(to: directory.appendingPathComponent("special_tokens_map.json"))
    try Data("{\"version\":\"1.0\",\"truncation\":null,\"padding\":null,\"added_tokens\":[],\"normalizer\":null,\"pre_tokenizer\":null,\"post_processor\":null,\"decoder\":null,\"model\":{\"type\":\"BPE\",\"vocab\":{},\"merges\":[]}}".utf8).write(to: directory.appendingPathComponent("tokenizer.json"))
    return directory
}

#if arch(arm64)
// MARK: - Mock engine

private final class MockOCREngine: PaddleOCRInferencing {
    var result: (text: String, confidence: Float) = ("テスト", 0.95)
    var errorToThrow: (any Error)?
    var callCount = 0

    func infer(image: CGImage) throws -> (text: String, confidence: Float) {
        callCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        return result
    }
}

private final class RecordingOCREngine: PaddleOCRInferencing {
    private(set) var lastImageSize: CGSize?
    var result: (text: String, confidence: Float) = ("テスト", 0.95)

    func infer(image: CGImage) throws -> (text: String, confidence: Float) {
        lastImageSize = CGSize(width: image.width, height: image.height)
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
        let dir = try makeModelDirectoryWithWeights()
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

    @Test("Nested model folder is resolved without moving files")
    func nestedModelFolderIsResolved() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nestedDir = rootDir.appendingPathComponent("paddleocr-vl-manga-mlx")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        try Data("fake-safetensors".utf8).write(to: nestedDir.appendingPathComponent("model.safetensors"))

        var enginePath: URL?
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: rootDir) { path in
            enginePath = path
            return MockOCREngine()
        }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        _ = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(enginePath != nil)
        #expect(enginePath?.resolvingSymlinksInPath().path == nestedDir.resolvingSymlinksInPath().path)
    }

    @Test("Root model.safetensors is treated as a valid model artifact")
    func rootSafetensorsIsAccepted() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        try Data("fake-safetensors".utf8).write(to: rootDir.appendingPathComponent("model.safetensors"))

        var enginePath: URL?
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: rootDir) { path in
            enginePath = path
            return MockOCREngine()
        }

        guard let image = makeSolidCGImage(width: 80, height: 40) else { return }
        _ = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 80, height: 40))
        #expect(enginePath?.resolvingSymlinksInPath().path == rootDir.resolvingSymlinksInPath().path)
    }

    @Test("Quantized-key mismatch maps to PaddleOCRError.verifyFailed")
    func quantizedKeyMismatchMapsToVerifyFailed() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.errorToThrow = PaddleOCREngineError.runtimeFailure(
            "Unhandled keys [\"biases\", \"scales\"] in vision_model.layers.0.mlp.fc1"
        )
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }
        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }

        #expect(throws: PaddleOCRError.verifyFailed) {
            _ = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))
        }
    }

    // MARK: - Task 34: Boundary tests

    @Test("Region exceeding image bounds is clamped — no crash")
    func regionExceedsBoundsIsClamped() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        // Region extends beyond image bounds
        let region = CGRect(x: 50, y: 25, width: 200, height: 200)
        let result = try recognizer.recognizeText(in: image, region: region)

        #expect(result.text == "テスト")
    }

    @Test("PaddleOCR crop expands region with padding before inference")
    func cropExpansionAddsPadding() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = RecordingOCREngine()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in engine }

        guard let image = makeSolidCGImage(width: 200, height: 100) else { return }
        _ = try recognizer.recognizeText(in: image, region: CGRect(x: 50, y: 20, width: 60, height: 30))

        #expect(engine.lastImageSize == CGSize(width: 92, height: 42))
    }

    @Test("PaddleOCR crop padding is clamped to image bounds near edges")
    func cropExpansionClampsNearEdges() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = RecordingOCREngine()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in engine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        _ = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 20, height: 10))

        #expect(engine.lastImageSize == CGSize(width: 32, height: 16))
    }

    @Test("Region with zero width returns empty string without crash")
    func zeroWidthRegionReturnsEmpty() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let region = CGRect(x: 10, y: 10, width: 0, height: 30)
        let (text, confidence) = try recognizer.recognizeText(in: image, region: region)

        #expect(text.isEmpty || confidence == 0)
    }

    @Test("Region with zero height returns empty string without crash")
    func zeroHeightRegionReturnsEmpty() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let region = CGRect(x: 10, y: 10, width: 30, height: 0)
        let (text, confidence) = try recognizer.recognizeText(in: image, region: region)

        #expect(text.isEmpty || confidence == 0)
    }

    @Test("All-white input image returns result without crashing")
    func allWhiteInputNoCrash() throws {
        let dir = try makeModelDirectoryWithWeights()
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
        let dir = try makeModelDirectoryWithWeights()
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
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in MockOCREngine() }

        guard let image = makeSolidCGImage(width: 3840, height: 2160) else { return }
        let region = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let result = try recognizer.recognizeText(in: image, region: region)

        #expect(result.confidence >= 0)
    }

    // MARK: - Task 35 / 36: Explicit unload hook

    @Test("unload() releases model resources deterministically")
    func explicitUnloadReleasesResources() throws {
        let dir = try makeModelDirectoryWithWeights()
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

    // MARK: - Memory pressure release

    @Test("Memory pressure notification releases model and reloads on next inference")
    func memoryPressureReleasesAndReloads() async throws {
        let dir = try makeModelDirectoryWithWeights()
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

        NotificationCenter.default.post(name: .paddleOCRVLMemoryPressure, object: nil)
        await Task.yield()

        _ = try recognizer.recognizeText(in: image, region: region)
        #expect(loadCount == 2, "Memory pressure should release model, forcing reload on next inference")
    }

    // MARK: - Decode-stability: cleanRecognizedText

    @Test("Repeated punctuation tail is collapsed to a single character")
    func repeatedPunctuationIsCollapsed() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("Degraded output...............", 0.8)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let (text, _) = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(text == "Degraded output.", "Repeated dots should be collapsed to one period, not replaced with '['")
    }

    @Test("Replacement characters are stripped from PaddleOCR output")
    func replacementCharactersAreRemoved() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("さぁ�いってきてください!!", 0.8)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let (text, _) = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(text == "さぁいってきてください!!")
    }

    @Test("Repeated phrase loop is stripped to its first occurrence")
    func repeatedPhraseTailIsStripped() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("This is a loop. This is a loop. This is a loop. This is a loop.", 0.9)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let (text, _) = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(text == "This is a loop.", "Repeated phrase tail should be stripped to a single occurrence")
    }

    @Test("Default engine reports explicit inference failure instead of silent empty result")
    func defaultEngineReturnsExplicitFailure() throws {
        let dir = try makeModelDirectoryWithRuntimeArtifacts()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir)
        guard let image = makeSolidCGImage(width: 120, height: 60) else { return }

        do {
            _ = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 120, height: 60))
            Issue.record("Expected default engine to throw")
        } catch let error as PaddleOCRError {
            switch error {
            case .inferenceFailed(let message):
                #expect(!message.isEmpty)
            default:
                Issue.record("Expected inferenceFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected PaddleOCRError, got \(error)")
        }
    }
}

@Suite("DefaultPaddleOCREngine")
@MainActor
struct DefaultPaddleOCREngineTests {
    @Test("effectiveMaxNewTokens respects generation config ceiling")
    func effectiveMaxNewTokensRespectsConfig() {
        #expect(effectiveMaxNewTokens(requested: 1024, configured: 300) == 300)
        #expect(effectiveMaxNewTokens(requested: 120, configured: 300) == 120)
        #expect(effectiveMaxNewTokens(requested: 0, configured: 300) == 1)
    }

    @Test("no-repeat ngram guard blocks repeated trigram continuation")
    func noRepeatNgramGuardBlocksRepeatedTrigram() {
        let tokens = [10, 11, 12, 10, 11]
        #expect(wouldRepeatNgram(generatedTokens: tokens, nextTokenId: 12, noRepeatNgramSize: 3))
        #expect(!wouldRepeatNgram(generatedTokens: tokens, nextTokenId: 13, noRepeatNgramSize: 3))
        #expect(!wouldRepeatNgram(generatedTokens: [10], nextTokenId: 10, noRepeatNgramSize: 3))
    }

    @Test("infer throws runtimeFailure when model artifacts cannot be fully loaded")
    func inferThrowsRuntimeFailure() throws {
        let dir = try makeModelDirectoryWithRuntimeArtifacts()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try DefaultPaddleOCREngine(modelDirectory: dir)
        guard let image = makeSolidCGImage(width: 80, height: 40) else { return }

        do {
            _ = try engine.infer(image: image)
            Issue.record("Expected runtimeFailure")
        } catch let error as PaddleOCREngineError {
            switch error {
            case .runtimeFailure(let message):
                #expect(!message.isEmpty)
            default:
                Issue.record("Expected runtimeFailure, got \(error)")
            }
        } catch {
            Issue.record("Expected PaddleOCREngineError, got \(error)")
        }
    }

    @Test("init throws modelUnavailable when weights are missing")
    func initThrowsWhenWeightsMissing() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: PaddleOCREngineError.modelUnavailable) {
            _ = try DefaultPaddleOCREngine(modelDirectory: dir)
        }
    }
}
#endif
