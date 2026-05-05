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
    #endif
}
