import Testing
import Foundation
import AppKit

#if arch(arm64)
@testable import MangaTranslatorMLX

@Suite("PaddleOCR Integration Spike")
@MainActor
struct PaddleOCRIntegrationSpikeTests {
    @Test("Native engine can run against local converted model artifacts")
    func nativeEngineSpike() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MangaTranslatorSpikeTests
            .deletingLastPathComponent() // repo root

        let modelDir = repoRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("convert_model")
            .appendingPathComponent("mlx_output")
        let imageURL = repoRoot
            .appendingPathComponent("test_images")
            .appendingPathComponent("001.jpg")

        // Skip if model artifacts are not present (opt-in by having the model files)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return
        }
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Missing spike image: \(imageURL.path)")
            return
        }

        let engine = try DefaultPaddleOCREngine(modelDirectory: modelDir)
        let clock = ContinuousClock()

        let start1 = clock.now
        let first = try engine.infer(image: cgImage)
        let elapsed1 = start1.duration(to: clock.now).components
        let firstMs = Double(elapsed1.seconds) * 1000
            + Double(elapsed1.attoseconds) / 1e15

        let start2 = clock.now
        let second = try engine.infer(image: cgImage)
        let elapsed2 = start2.duration(to: clock.now).components
        let secondMs = Double(elapsed2.seconds) * 1000
            + Double(elapsed2.attoseconds) / 1e15

        let resultLine = "PaddleOCR spike first_run_ms=\(firstMs) warm_run_ms=\(secondMs) first_len=\(first.text.count) warm_len=\(second.text.count)\nfirst=[\(first.text)]\nsecond=[\(second.text)]"
        print(resultLine)
        try? resultLine.write(toFile: "/tmp/paddle_ocr_spike_result.txt", atomically: true, encoding: .utf8)

        #expect(!first.text.isEmpty || !second.text.isEmpty)
        #expect(firstMs < 120_000)
        #expect(secondMs < 60_000)
    }
}
#endif
