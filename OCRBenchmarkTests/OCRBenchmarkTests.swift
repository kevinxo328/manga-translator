import XCTest
@testable import MangaTranslator
import AppKit

final class OCRBenchmarkTests: XCTestCase {
    private let scanner = ImageScanner()
    private let reporter = BenchmarkReporter()

    private var projectRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // OCRBenchmarkTests/
            .deletingLastPathComponent()  // project root
    }

    private var examplesDir: URL {
        projectRoot.appendingPathComponent("examples")
    }

    // Task 3.4 - empty directory guard: report contains no-images warning
    func testEmptyExamplesProducesNoImagesWarning() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let images = scanner.findImages(in: tmpDir)
        XCTAssertTrue(images.isEmpty)
        let result = BenchmarkResult(timestamp: Date(), imageCount: 0, imageResults: [])
        let report = reporter.generateReport(from: result)
        XCTAssertTrue(report.contains("No images found"))
    }

    // Task 3.5 - integration test: full pipeline on a single known test image
    func testSingleImagePipeline() async throws {
        let images = scanner.findImages(in: examplesDir)
        guard let firstImageURL = images.first else {
            print("No images in examples/ — skipping integration test")
            return
        }
        guard let nsImage = NSImage(contentsOf: firstImageURL) else {
            XCTFail("Could not load image: \(firstImageURL.path)")
            return
        }

        let mangaService = MangaOCRService()
        let visionService = VisionOCRService()
        let bubbleDetector = BubbleDetector()

        let mangaBubbles = try mangaService.recognizeAndCluster(in: nsImage)
        let visionObservations = try await visionService.recognizeText(in: nsImage)
        let visionBubbles = bubbleDetector.detectBubbles(from: visionObservations)

        let result = BubbleRegionMatcher.match(manga: mangaBubbles, vision: visionBubbles)
        print("Image: \(firstImageURL.path), Manga bubbles: \(mangaBubbles.count), Vision bubbles: \(visionBubbles.count), Paired: \(result.paired.count)")
    }

    // Task 3.6 - full benchmark: scan → detect → IoU → dual OCR → report
    func testFullBenchmark() async throws {
        let images = scanner.findImages(in: examplesDir)
        guard !images.isEmpty else {
            print("No images in examples/ — skipping full benchmark")
            return
        }

        let mangaService = MangaOCRService()
        let visionService = VisionOCRService()
        let bubbleDetector = BubbleDetector()

        var imageResults: [ImageResult] = []

        for imagePath in images {
            guard let nsImage = NSImage(contentsOf: imagePath) else {
                continue
            }

            let mangaBubbles: [BubbleCluster]
            do {
                mangaBubbles = try mangaService.recognizeAndCluster(in: nsImage)
            } catch {
                print("MangaOCR failed for \(imagePath.lastPathComponent): \(error)")
                mangaBubbles = []
            }

            let visionBubbles: [BubbleCluster]
            do {
                let obs = try await visionService.recognizeText(in: nsImage)
                visionBubbles = bubbleDetector.detectBubbles(from: obs)
            } catch {
                print("VisionOCR failed for \(imagePath.lastPathComponent): \(error)")
                visionBubbles = []
            }

            let matchResult = BubbleRegionMatcher.match(manga: mangaBubbles, vision: visionBubbles)
            
            imageResults.append(ImageResult(
                imagePath: imagePath.path,
                pairedRegions: matchResult.paired,
                unmatchedManga: matchResult.unmatchedManga,
                unmatchedVision: matchResult.unmatchedVision
            ))
        }

        let result = BenchmarkResult(
            timestamp: Date(),
            imageCount: images.count,
            imageResults: imageResults
        )

        let report = reporter.generateReport(from: result)

        // Print to Xcode console for immediate viewing
        print("\n" + report + "\n")

        // Also attach to test result for history
        let attachment = XCTAttachment(string: report)
        attachment.name = "benchmark-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(imageResults.isEmpty, "Expected results for at least one image")
    }
}
