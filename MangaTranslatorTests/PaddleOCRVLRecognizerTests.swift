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

    @Test("Repeated punctuation tail is preserved for verify parity")
    func repeatedPunctuationIsPreserved() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("Degraded output...............", 0.8)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let (text, _) = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(text == "Degraded output...............")
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

    @Test("Repeated phrase loop is preserved for verify parity")
    func repeatedPhraseLoopIsPreserved() throws {
        let dir = try makeModelDirectoryWithWeights()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockEngine = MockOCREngine()
        mockEngine.result = ("This is a loop. This is a loop. This is a loop. This is a loop.", 0.9)
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: dir) { _ in mockEngine }

        guard let image = makeSolidCGImage(width: 100, height: 50) else { return }
        let (text, _) = try recognizer.recognizeText(in: image, region: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(text == "This is a loop. This is a loop. This is a loop. This is a loop.")
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

// MARK: - Multimodal Position ID tests

@Suite("MultimodalPositionIds")
struct MultimodalPositionIdsTests {

    // 2×2 grid: text_before=4 tokens, 4 image tokens, 2 text_after tokens
    @Test("2x2 grid: image tokens get correct t/h/w positions")
    func grid2x2ImagePositions() {
        let imageTokenId = 99
        // [bos, u1, u2, visStart, img(0,0), img(0,1), img(1,0), img(1,1), visEnd, task]
        let inputIds = [0, 1, 2, 3, imageTokenId, imageTokenId, imageTokenId, imageTokenId, 4, 5]
        let (positionIds, ropeDelta) = computeMultimodalPositionIds(
            inputIds: inputIds, hMerged: 2, wMerged: 2, imageTokenId: imageTokenId
        )

        #expect(ropeDelta == -2)  // max(2,2) - 4 = -2

        let (tIds, hIds, wIds) = extractPositionIdAxes(positionIds)

        // Text before: sequential positions 0-3
        #expect(tIds[0] == 0 && hIds[0] == 0 && wIds[0] == 0)
        #expect(tIds[3] == 3 && hIds[3] == 3 && wIds[3] == 3)

        let textBefore = Int32(4)
        // img(0,0): t=4, h=4+0=4, w=4+0=4
        #expect(tIds[4] == textBefore && hIds[4] == textBefore && wIds[4] == textBefore)
        // img(0,1): t=4, h=4, w=5
        #expect(tIds[5] == textBefore && hIds[5] == textBefore && wIds[5] == textBefore + 1)
        // img(1,0): t=4, h=5, w=4
        #expect(tIds[6] == textBefore && hIds[6] == textBefore + 1 && wIds[6] == textBefore)
        // img(1,1): t=4, h=5, w=5
        #expect(tIds[7] == textBefore && hIds[7] == textBefore + 1 && wIds[7] == textBefore + 1)

        // Text after: starts at textBefore + max(2,2) = 6
        #expect(tIds[8] == 6 && hIds[8] == 6 && wIds[8] == 6)
        #expect(tIds[9] == 7 && hIds[9] == 7 && wIds[9] == 7)
    }

    // Landscape grid (4 rows × 2 cols): max(h,w)=4, n_img=8, delta=-4
    @Test("4x2 grid: rope delta is max(h,w) - h*w")
    func grid4x2RopeDelta() {
        let imageTokenId = 99
        let inputIds = [0] + Array(repeating: imageTokenId, count: 8) + [1]
        let (_, ropeDelta) = computeMultimodalPositionIds(
            inputIds: inputIds, hMerged: 4, wMerged: 2, imageTokenId: imageTokenId
        )
        #expect(ropeDelta == -4)  // max(4,2) - 8 = -4
    }

    // Portrait grid (2 rows × 4 cols): max(h,w)=4, n_img=8, delta=-4
    @Test("2x4 grid: rope delta accounts for wider width")
    func grid2x4RopeDelta() {
        let imageTokenId = 99
        let inputIds = [0] + Array(repeating: imageTokenId, count: 8) + [1]
        let (_, ropeDelta) = computeMultimodalPositionIds(
            inputIds: inputIds, hMerged: 2, wMerged: 4, imageTokenId: imageTokenId
        )
        #expect(ropeDelta == -4)  // max(2,4) - 8 = -4
    }

    // 1×1 grid (single patch): max(1,1)=1, n_img=1, delta=0
    @Test("1x1 grid: rope delta is zero")
    func grid1x1RopeDelta() {
        let imageTokenId = 99
        let inputIds = [0, imageTokenId, 1]
        let (positionIds, ropeDelta) = computeMultimodalPositionIds(
            inputIds: inputIds, hMerged: 1, wMerged: 1, imageTokenId: imageTokenId
        )
        #expect(ropeDelta == 0)
        let (tIds, hIds, wIds) = extractPositionIdAxes(positionIds)
        // bos: (0,0,0), img: (1,1,1), task: (2,2,2)
        #expect(tIds[1] == 1 && hIds[1] == 1 && wIds[1] == 1)
        #expect(tIds[2] == 2 && hIds[2] == 2 && wIds[2] == 2)
    }

    // No image tokens: all sequential
    @Test("no image tokens: all positions sequential")
    func noImageTokens() {
        let inputIds = [0, 1, 2, 3]
        let (positionIds, ropeDelta) = computeMultimodalPositionIds(
            inputIds: inputIds, hMerged: 1, wMerged: 1, imageTokenId: 99
        )
        #expect(ropeDelta == 0)
        let (tIds, _, _) = extractPositionIdAxes(positionIds)
        #expect(tIds == [0, 1, 2, 3])
    }
}
#endif
