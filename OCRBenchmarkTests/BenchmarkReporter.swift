import Foundation
import CoreGraphics
@testable import MangaTranslator

struct OverlapWarning {
    let boxIndex: Int
    let overlappingIndices: [(index: Int, iou: Float)]
}

struct PairedRegionResult {
    let mangaBubble: BubbleCluster?
    let visionBubble: BubbleCluster?
    let iou: Float
}

struct ImageResult {
    let imagePath: String
    let pairedRegions: [PairedRegionResult]
    let unmatchedManga: [BubbleCluster]
    let unmatchedVision: [BubbleCluster]
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

        var totalPaired = 0
        var totalUnmatchedManga = 0
        var totalUnmatchedVision = 0
        var mangaFailures = 0 // Images where MangaOCR produced 0 bubbles
        var visionFailures = 0 // Images where VisionOCR produced 0 bubbles

        for imgResult in result.imageResults {
            lines += ["", "--- \(imgResult.imagePath) ---"]
            
            if imgResult.pairedRegions.isEmpty && imgResult.unmatchedManga.isEmpty {
                mangaFailures += 1
            }
            if imgResult.pairedRegions.isEmpty && imgResult.unmatchedVision.isEmpty {
                visionFailures += 1
            }

            // Paired Regions
            lines.append("Paired Regions: \(imgResult.pairedRegions.count)")
            for (i, paired) in imgResult.pairedRegions.enumerated() {
                totalPaired += 1
                let rect = paired.mangaBubble?.boundingBox ?? paired.visionBubble?.boundingBox ?? .zero
                lines += ["", "  Pair \(i + 1): \(rect) (IoU: \(String(format: "%.2f", paired.iou)))"]
                lines.append("  MangaOCR: \(paired.mangaBubble?.text ?? "[empty]")")
                lines.append("  VisionOCR: \(paired.visionBubble?.text ?? "[empty]")")
            }

            // Unmatched MangaOCR
            if !imgResult.unmatchedManga.isEmpty {
                lines += ["", "  [Unmatched MangaOCR]"]
                for bubble in imgResult.unmatchedManga {
                    totalUnmatchedManga += 1
                    lines.append("  - \(bubble.boundingBox): \(bubble.text)")
                }
            }

            // Unmatched Vision
            if !imgResult.unmatchedVision.isEmpty {
                lines += ["", "  [Unmatched Vision]"]
                for bubble in imgResult.unmatchedVision {
                    totalUnmatchedVision += 1
                    lines.append("  - \(bubble.boundingBox): \(bubble.text)")
                }
            }
        }

        lines += ["", "=== Summary ===",
                  "Total paired: \(totalPaired)",
                  "Unmatched MangaOCR: \(totalUnmatchedManga)",
                  "Unmatched Vision: \(totalUnmatchedVision)",
                  "MangaOCR image failures: \(mangaFailures)",
                  "VisionOCR image failures: \(visionFailures)"]
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
