import XCTest
import CoreGraphics

final class BenchmarkReporterTests: XCTestCase {
    let reporter = BenchmarkReporter()

    // Task 2.3 - overlap detection flags larger box at threshold 0.5
    func testOverlapDetectionFlagsLargerBox() {
        // large (0,0,100,100) area=10000, small (0,0,80,80) area=6400
        // intersection=6400, union=10000, IoU=0.64 > 0.5 → large flagged
        let large = CGRect(x: 0, y: 0, width: 100, height: 100)
        let small = CGRect(x: 0, y: 0, width: 80, height: 80)
        let warnings = reporter.detectOverlaps(in: [large, small])
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings.contains { $0.boxIndex == 0 })
    }

    func testBelowThresholdNoWarning() {
        // IoU=0.09 < 0.5 → no warning
        let large = CGRect(x: 0, y: 0, width: 100, height: 100)
        let small = CGRect(x: 10, y: 10, width: 30, height: 30)
        let warnings = reporter.detectOverlaps(in: [large, small])
        XCTAssertTrue(warnings.isEmpty)
    }

    func testNoOverlapNoWarnings() {
        let a = CGRect(x: 0, y: 0, width: 50, height: 50)
        let b = CGRect(x: 100, y: 100, width: 50, height: 50)
        XCTAssertTrue(reporter.detectOverlaps(in: [a, b]).isEmpty)
    }

    // Task 2.5 - report formatting: header
    func testReportHeader() {
        let result = BenchmarkResult(timestamp: Date(), imageCount: 2, imageResults: [])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("OCR Benchmark Report"))
        XCTAssertTrue(report.contains("Images processed: 2"))
    }

    func testReportPerImageSection() {
        let region = RegionResult(index: 0, rect: .zero, mangaOCRText: "日本語",
                                  visionOCRText: "日本語", overlapWarnings: [])
        let imageResult = ImageResult(imagePath: "test.jpg", regions: [region])
        let result = BenchmarkResult(timestamp: Date(), imageCount: 1, imageResults: [imageResult])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("test.jpg"))
        XCTAssertTrue(report.contains("MangaOCR: 日本語"))
        XCTAssertTrue(report.contains("VisionOCR: 日本語"))
    }

    func testReportSummarySection() {
        let result = BenchmarkResult(timestamp: Date(), imageCount: 1, imageResults: [])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("Summary"))
        XCTAssertTrue(report.contains("Total regions:"))
        XCTAssertTrue(report.contains("Overlap warnings:"))
        XCTAssertTrue(report.contains("MangaOCR failures:"))
        XCTAssertTrue(report.contains("VisionOCR failures:"))
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
