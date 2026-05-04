import Foundation
import CoreGraphics

struct OverlapWarning {
    let boxIndex: Int
    let overlappingIndices: [(index: Int, iou: Float)]
}

struct RegionResult {
    let index: Int
    let rect: CGRect
    let mangaOCRText: String
    let visionOCRText: String
    let overlapWarnings: [OverlapWarning]
}

struct ImageResult {
    let imagePath: String
    let regions: [RegionResult]
}

struct BenchmarkResult {
    let timestamp: Date
    let imageCount: Int
    let imageResults: [ImageResult]
    var noImagesWarning: Bool { imageCount == 0 }
}

struct BenchmarkReporter {

    func detectOverlaps(in boxes: [CGRect]) -> [OverlapWarning] {
        var warnings: [OverlapWarning] = []
        for i in 0..<boxes.count {
            var overlapping: [(index: Int, iou: Float)] = []
            for j in 0..<boxes.count where j != i {
                let score = IoUCalculator.iou(boxes[i], boxes[j])
                if score > 0.5 {
                    let areaI = boxes[i].width * boxes[i].height
                    let areaJ = boxes[j].width * boxes[j].height
                    if areaI >= areaJ {
                        overlapping.append((index: j, iou: score))
                    }
                }
            }
            if !overlapping.isEmpty {
                warnings.append(OverlapWarning(boxIndex: i, overlappingIndices: overlapping))
            }
        }
        return warnings
    }

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

        var totalRegions = 0
        var totalOverlapWarnings = 0
        var mangaFailures = 0
        var visionFailures = 0

        for imgResult in result.imageResults {
            lines += ["", "--- \(imgResult.imagePath) ---",
                      "Regions detected: \(imgResult.regions.count)"]
            for region in imgResult.regions {
                totalRegions += 1
                lines += ["", "  Region \(region.index + 1): \(region.rect)"]
                let manga = region.mangaOCRText
                lines.append("  MangaOCR: \(manga.isEmpty ? "[empty]" : manga)")
                if manga.isEmpty { mangaFailures += 1 }
                let vision = region.visionOCRText
                lines.append("  VisionOCR: \(vision.isEmpty ? "[empty]" : vision)")
                if vision.isEmpty { visionFailures += 1 }
                for warning in region.overlapWarnings {
                    totalOverlapWarnings += 1
                    let details = warning.overlappingIndices
                        .map { "region \($0.index + 1) (IoU=\(String(format: "%.2f", $0.iou)))" }
                        .joined(separator: ", ")
                    lines.append("  WARNING: Overlaps with \(details)")
                }
            }
        }

        lines += ["", "=== Summary ===",
                  "Total regions: \(totalRegions)",
                  "Overlap warnings: \(totalOverlapWarnings)",
                  "MangaOCR failures: \(mangaFailures)",
                  "VisionOCR failures: \(visionFailures)"]
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
