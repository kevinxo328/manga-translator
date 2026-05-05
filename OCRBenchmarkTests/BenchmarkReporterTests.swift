import XCTest
import CoreGraphics
@testable import MangaTranslator

final class BenchmarkReporterTests: XCTestCase {
    let reporter = BenchmarkReporter()

    // Task 2.5 - report formatting: header
    func testReportHeader() {
        let result = BenchmarkResult(timestamp: Date(), imageCount: 2, imageResults: [])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("OCR Benchmark Report"))
        XCTAssertTrue(report.contains("Images processed: 2"))
    }

    func testReportPerImageSection() {
        let paddle = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100), text: "Paddle Text", observations: [])
        let manga = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100), text: "Manga Text", observations: [])
        let vision = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100), text: "Vision Text", observations: [])
        
        let paddleVsManga = PairedRegionResult(anchorBubble: paddle, comparedBubble: manga, iou: 1.0)
        let paddleVsVision = PairedRegionResult(anchorBubble: paddle, comparedBubble: vision, iou: 1.0)
        
        let unmatchedM = BubbleCluster(boundingBox: CGRect(x: 200, y: 0, width: 50, height: 50), text: "Only Manga", observations: [])
        let unmatchedV = BubbleCluster(boundingBox: CGRect(x: 0, y: 200, width: 50, height: 50), text: "Only Vision", observations: [])
        let unmatchedP = BubbleCluster(boundingBox: CGRect(x: 300, y: 300, width: 50, height: 50), text: "Only Paddle", observations: [])
        
        let imageResult = ImageResult(
            imagePath: "test.jpg",
            paddleVsManga: [paddleVsManga],
            paddleVsVision: [paddleVsVision],
            unmatchedPaddleManga: [unmatchedP],
            unmatchedPaddleVision: [],
            unmatchedManga: [unmatchedM],
            unmatchedVision: [unmatchedV],
            latency: ["PaddleOCR": 150.0, "MangaOCR": 100.0],
            failures: ["Vision"]
        )
        let result = BenchmarkResult(timestamp: Date(), imageCount: 1, imageResults: [imageResult])
        let report = reporter.generateReport(from: result)
        
        XCTAssertTrue(report.contains("test.jpg"))
        XCTAssertTrue(report.contains("PaddleOCR vs MangaOCR Paired: 1"))
        XCTAssertTrue(report.contains("PaddleOCR vs Vision OCR Paired: 1"))
        XCTAssertTrue(report.contains("IoU: 1.00"))
        XCTAssertTrue(report.contains("PaddleOCR: Paddle Text"))
        XCTAssertTrue(report.contains("MangaOCR: Manga Text"))
        XCTAssertTrue(report.contains("VisionOCR: Vision Text"))
        XCTAssertTrue(report.contains("[Unmatched PaddleOCR (vs Manga)]"))
        XCTAssertTrue(report.contains("Only Paddle"))
        XCTAssertTrue(report.contains("[Unmatched MangaOCR]"))
        XCTAssertTrue(report.contains("Only Manga"))
        XCTAssertTrue(report.contains("[Unmatched Vision]"))
        XCTAssertTrue(report.contains("Only Vision"))
        XCTAssertTrue(report.contains("Latency:"))
        XCTAssertTrue(report.contains("PaddleOCR: 150.00ms"))
        XCTAssertTrue(report.contains("MangaOCR: 100.00ms"))
    }

    func testReportSummarySection() {
        let result = BenchmarkResult(timestamp: Date(), imageCount: 1, imageResults: [])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("=== Summary ==="))
        XCTAssertTrue(report.contains("PaddleOCR vs MangaOCR paired:"))
        XCTAssertTrue(report.contains("PaddleOCR vs Vision paired:"))
        XCTAssertTrue(report.contains("Unmatched PaddleOCR (vs Manga):"))
        XCTAssertTrue(report.contains("Unmatched PaddleOCR (vs Vision):"))
        XCTAssertTrue(report.contains("Unmatched MangaOCR:"))
        XCTAssertTrue(report.contains("Unmatched Vision:"))
        XCTAssertTrue(report.contains("PaddleOCR image failures:"))
        XCTAssertTrue(report.contains("MangaOCR image failures:"))
        XCTAssertTrue(report.contains("Vision image failures:"))
    }

    func testNoImagesWarningInReport() {
        let result = BenchmarkResult(timestamp: Date(), imageCount: 0, imageResults: [])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("WARNING"))
        XCTAssertTrue(report.contains("No images found"))
    }

    // Task 2.7 - output directory creation when missing
    func testCreatesOutputDirectoryIfMissing() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("output").path))

        let result = BenchmarkResult(timestamp: Date(), imageCount: 0, imageResults: [])
        try reporter.write(result: result, to: tmpDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("output").path))
    }

    func testWritesTimestampedFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let result = BenchmarkResult(timestamp: Date(), imageCount: 0, imageResults: [])
        try reporter.write(result: result, to: tmpDir)

        let files = try FileManager.default.contentsOfDirectory(
            atPath: tmpDir.appendingPathComponent("output").path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasPrefix("report-"))
        XCTAssertTrue(files[0].hasSuffix(".txt"))
    }
}
