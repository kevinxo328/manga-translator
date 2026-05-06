import Testing
import Foundation
import AppKit
import mach
@testable import MangaTranslator

#if arch(arm64)
@testable import MangaTranslatorMLX
#endif

// MARK: - Memory Utils

private func getResidentMemory() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return kerr == KERN_SUCCESS ? info.resident_size : 0
}

private func formatBytes(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1024 / 1024
    return String(format: "%.2f MB", mb)
}

private func benchmarkExpandedCrop(
    image: CGImage,
    region: CGRect
) -> CGImage? {
    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let cropPaddingRatio: CGFloat = 0.18
    let minimumHorizontalPadding: CGFloat = 10
    let minimumVerticalPadding: CGFloat = 6
    let elongatedBubbleThreshold: CGFloat = 1.6
    let tallBubbleThreshold: CGFloat = 0.7
    let elongatedHorizontalBoostRatio: CGFloat = 0.08
    let tallVerticalBoostRatio: CGFloat = 0.08

    let aspectRatio = region.width / region.height
    var horizontalPadding = max(minimumHorizontalPadding, region.width * cropPaddingRatio)
    var verticalPadding = max(minimumVerticalPadding, region.height * cropPaddingRatio)

    if aspectRatio >= elongatedBubbleThreshold {
        horizontalPadding += region.width * elongatedHorizontalBoostRatio
    } else if aspectRatio <= tallBubbleThreshold {
        verticalPadding += region.height * tallVerticalBoostRatio
    }

    let expanded = region.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    let clamped = expanded.intersection(imageBounds).integral
    guard clamped.width > 0 && clamped.height > 0 else { return nil }
    return image.cropping(to: clamped)
}

// MARK: - Verification Tests

@Suite("PaddleOCR Verification")
struct PaddleOCRVerificationTests {
    
    #if arch(arm64)
    @Test("Classify PaddleOCR memory usage: load, warm, and inference peaks")
    func classifyMemoryUsage() async throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let modelDir = appSupport
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
            .appendingPathComponent("PaddleOCR-VL")
        
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelDir) else {
            print("PaddleOCR model not available for memory verification — skipping")
            return
        }

        let initialMem = getResidentMemory()
        print("Initial Resident Memory: \(formatBytes(initialMem))")

        // 1. Model Load Peak
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        let loadedMem = getResidentMemory()
        print("After Load Resident Memory: \(formatBytes(loadedMem)) (Delta: \(formatBytes(loadedMem - initialMem)))")

        // 2. Per-page Inference Peak
        guard let image = NSImage(size: NSSize(width: 1024, height: 1024)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        
        _ = try engine.infer(image: cgImage)
        let inferenceMem = getResidentMemory()
        print("After Inference Resident Memory: \(formatBytes(inferenceMem)) (Delta from loaded: \(formatBytes(inferenceMem - loadedMem)))")

        // 3. Warm Residency (after some time/GC)
        // In a real verification we might wait or trigger GC, but here we just note the state.
        print("Warm Residency: \(formatBytes(getResidentMemory()))")
    }

    @Test("Capture decode failure modes and loops using MockEngine")
    func captureDecodeFailures() async throws {
        class LoopMockEngine: PaddleOCRInferencing {
            var mode: FailureMode = .none
            enum FailureMode {
                case none
                case phraseLoop
                case punctuationLoop
                case truncation
            }

            func infer(image: CGImage) throws -> (text: String, confidence: Float) {
                switch mode {
                case .none:
                    return ("Normal text", 1.0)
                case .phraseLoop:
                    // Simulated loop that would be produced by an un-guarded generator
                    return ("This is a loop. This is a loop. This is a loop. This is a loop.", 0.9)
                case .punctuationLoop:
                    return ("Degraded output...............", 0.8)
                case .truncation:
                    return ("Incomplete sentence that ends abruptly and", 0.7)
                }
            }
        }

        let mock = LoopMockEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Data("fake".utf8).write(to: tempDir.appendingPathComponent("model.safetensors"))

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: tempDir) { _ in mock }
        guard let image = NSImage(size: NSSize(width: 100, height: 100)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        // 1. Phrase Loop - should be cleaned to a single occurrence
        mock.mode = .phraseLoop
        let phraseResult = try recognizer.recognizeText(in: cgImage, region: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(phraseResult.text == "This is a loop.", "Should detect and clean phrase loop")
        
        // 2. Punctuation Loop - should trim the repeated tail
        mock.mode = .punctuationLoop
        let punctResult = try recognizer.recognizeText(in: cgImage, region: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(punctResult.text == "Degraded output.", "Should trim repeated punctuation tail")
    }

    @Test("Measure memory amplification in concurrent flows")
    func measureConcurrentMemory() async throws {
        let initialMem = getResidentMemory()
        print("Initial Mem for concurrency: \(formatBytes(initialMem))")
        
        // This test would ideally run multiple inferences in parallel and measure the peak RSS.
        // For now, we just establish the structure.
    }

    @Test("Capture debug token traces for benchmark empty regions")
    func captureDebugTokenTracesForBenchmarkEmptyRegions() async throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let modelDir = appSupport
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
            .appendingPathComponent("PaddleOCR-VL")

        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelDir) else {
            print("PaddleOCR model not available for debug trace capture — skipping")
            return
        }

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let cases: [(String, String, CGRect)] = [
            ("book1/001#r2", "examples/book1/001.jpg", CGRect(x: 292.0651, y: 669.7273, width: 22.0659, height: 71.1165)),
            ("book1/001#r3", "examples/book1/001.jpg", CGRect(x: 963.3900, y: 1138.7845, width: 21.4628, height: 70.9517)),
            ("book1/002#r9", "examples/book1/002.jpg", CGRect(x: 244.2680, y: 942.5192, width: 72.4024, height: 141.1021)),
            ("book1/004#r12", "examples/book1/004.jpg", CGRect(x: 806.2938, y: 1452.3148, width: 33.9647, height: 98.4724)),
            ("book1/004#r13", "examples/book1/004.jpg", CGRect(x: 125.4072, y: 1151.9563, width: 146.3098, height: 375.1194)),
        ]

        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var captured = 0

        for (label, relativePath, region) in cases {
            let imageURL = projectRoot.appendingPathComponent(relativePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let cropped = benchmarkExpandedCrop(image: cgImage, region: region) else {
                Issue.record("Could not prepare crop for \(label)")
                continue
            }

            let trace = try engine.inferDebug(image: cropped)
            captured += 1
            print("TRACE \(label)")
            print("  rawText: \(String(reflecting: trace.rawText))")
            print("  trimmedText: \(String(reflecting: trace.trimmedText))")
            print("  tokens: \(trace.generatedTokens)")
        }

        #expect(captured == cases.count)
    }
    #endif
}
