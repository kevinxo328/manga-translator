import Foundation
import CoreGraphics
@testable import MangaTranslator

struct OverlapWarning {
    let boxIndex: Int
    let overlappingIndices: [(index: Int, iou: Float)]
}

struct PairedRegionResult {
    let anchorBubble: BubbleCluster? // PaddleOCR
    let comparedBubble: BubbleCluster? // MangaOCR or Vision
    let iou: Float
}

struct ImageResult {
    let imagePath: String
    let paddleVsManga: [PairedRegionResult]
    let paddleVsVision: [PairedRegionResult]
    let unmatchedPaddleManga: [BubbleCluster]
    let unmatchedPaddleVision: [BubbleCluster]
    let unmatchedManga: [BubbleCluster]
    let unmatchedVision: [BubbleCluster]
    let latency: [String: Double] // engine id -> ms
    let failures: Set<String> // engine ids that failed
}

struct BenchmarkResult {
    let timestamp: Date
    let imageCount: Int
    let imageResults: [ImageResult]
    var noImagesWarning: Bool { imageCount == 0 }
}

struct BenchmarkReporter {

    func generateReport(from result: BenchmarkResult) -> String {
        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines: [String] = [
            "=== OCR Benchmark Report ===",
            "Generated: \(tsFormatter.string(from: result.timestamp))",
            "Images processed: \(result.imageCount)",
        ]

        if result.noImagesWarning {
            lines += ["", "WARNING: No images found in examples/ directory.",
                      "Place images under examples/ to run the benchmark."]
            return lines.joined(separator: "\n")
        }

        var totalPaddleVsManga = 0
        var totalPaddleVsVision = 0
        var totalUnmatchedPaddleManga = 0
        var totalUnmatchedPaddleVision = 0
        var totalUnmatchedManga = 0
        var totalUnmatchedVision = 0
        
        var engineFailures: [String: Int] = [:]

        for imgResult in result.imageResults {
            lines += ["", "--- \(imgResult.imagePath) ---"]

            for engineId in imgResult.failures {
                engineFailures[engineId, default: 0] += 1
            }

            // Latency
            if !imgResult.latency.isEmpty {
                lines.append("Latency:")
                for (engine, ms) in imgResult.latency.sorted(by: { $0.key < $1.key }) {
                    lines.append("  \(engine): \(String(format: "%.2f", ms))ms")
                }
            }

            // PaddleOCR vs MangaOCR
            lines.append("PaddleOCR vs MangaOCR Paired: \(imgResult.paddleVsManga.count)")
            for (i, paired) in imgResult.paddleVsManga.enumerated() {
                totalPaddleVsManga += 1
                let rect = paired.anchorBubble?.boundingBox ?? paired.comparedBubble?.boundingBox ?? .zero
                lines += ["", "  Pair \(i + 1): \(rect) (IoU: \(String(format: "%.2f", paired.iou)))"]
                lines.append("  PaddleOCR: \(paired.anchorBubble?.text ?? "[empty]")")
                lines.append("  MangaOCR: \(paired.comparedBubble?.text ?? "[empty]")")
            }

            if !imgResult.unmatchedPaddleManga.isEmpty {
                lines += ["", "  [Unmatched PaddleOCR (vs Manga)]"]
                for bubble in imgResult.unmatchedPaddleManga {
                    totalUnmatchedPaddleManga += 1
                    lines.append("  - \(bubble.boundingBox): \(bubble.text)")
                }
            }

            if !imgResult.unmatchedManga.isEmpty {
                lines += ["", "  [Unmatched MangaOCR]"]
                for bubble in imgResult.unmatchedManga {
                    totalUnmatchedManga += 1
                    lines.append("  - \(bubble.boundingBox): \(bubble.text)")
                }
            }

            // PaddleOCR vs Vision
            lines += ["", "PaddleOCR vs Vision OCR Paired: \(imgResult.paddleVsVision.count)"]
            for (i, paired) in imgResult.paddleVsVision.enumerated() {
                totalPaddleVsVision += 1
                let rect = paired.anchorBubble?.boundingBox ?? paired.comparedBubble?.boundingBox ?? .zero
                lines += ["", "  Pair \(i + 1): \(rect) (IoU: \(String(format: "%.2f", paired.iou)))"]
                lines.append("  PaddleOCR: \(paired.anchorBubble?.text ?? "[empty]")")
                lines.append("  VisionOCR: \(paired.comparedBubble?.text ?? "[empty]")")
            }

            if !imgResult.unmatchedPaddleVision.isEmpty {
                lines += ["", "  [Unmatched PaddleOCR (vs Vision)]"]
                for bubble in imgResult.unmatchedPaddleVision {
                    totalUnmatchedPaddleVision += 1
                    lines.append("  - \(bubble.boundingBox): \(bubble.text)")
                }
            }

            if !imgResult.unmatchedVision.isEmpty {
                lines += ["", "  [Unmatched Vision]"]
                for bubble in imgResult.unmatchedVision {
                    totalUnmatchedVision += 1
                    lines.append("  - \(bubble.boundingBox): \(bubble.text)")
                }
            }
        }

        lines += ["", "=== Summary ===",
                  "PaddleOCR vs MangaOCR paired: \(totalPaddleVsManga)",
                  "PaddleOCR vs Vision paired: \(totalPaddleVsVision)",
                  "Unmatched PaddleOCR (vs Manga): \(totalUnmatchedPaddleManga)",
                  "Unmatched PaddleOCR (vs Vision): \(totalUnmatchedPaddleVision)",
                  "Unmatched MangaOCR: \(totalUnmatchedManga)",
                  "Unmatched Vision: \(totalUnmatchedVision)"]
        
        for engine in ["PaddleOCR", "MangaOCR", "Vision"].sorted() {
            let count = engineFailures[engine] ?? 0
            lines.append("\(engine) image failures: \(count)")
        }

        return lines.joined(separator: "\n")
    }

    func write(result: BenchmarkResult, to baseDirectory: URL) throws {
        let outputDir = baseDirectory.appendingPathComponent("output")
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        let fileFormatter = DateFormatter()
        fileFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "report-\(fileFormatter.string(from: result.timestamp)).txt"
        let report = generateReport(from: result)
        try report.write(to: outputDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
}
