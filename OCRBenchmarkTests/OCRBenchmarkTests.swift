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
    func testSingleImagePipeline() throws {
        let images = scanner.findImages(in: examplesDir)
        guard let firstImageURL = images.first else {
            print("No images in examples/ — skipping integration test")
            return
        }
        guard let nsImage = NSImage(contentsOf: firstImageURL) else {
            XCTFail("Could not load image: \(firstImageURL.path)")
            return
        }

        let detector = ComicTextDetectorService()
        let detections = try detector.detectTextRegions(in: nsImage)
        XCTAssertFalse(detections.isEmpty, "Expected at least one detection in \(firstImageURL.lastPathComponent)")

        let boxes = detections.map(\.boundingBox)
        let warnings = reporter.detectOverlaps(in: boxes)
        print("Image: \(firstImageURL.lastPathComponent), detections: \(detections.count), overlap warnings: \(warnings.count)")
    }

    // Task 3.6 - full benchmark: scan → detect → IoU → dual OCR → report
    func testFullBenchmark() async throws {
        let images = scanner.findImages(in: examplesDir)
        guard !images.isEmpty else {
            print("No images in examples/ — skipping full benchmark")
            return
        }

        let detector = ComicTextDetectorService()
        let visionOCR = VisionOCRService()
        var mangaRecognizer: MangaOCRRecognizer?

        var imageResults: [ImageResult] = []

        for imagePath in images {
            guard let nsImage = NSImage(contentsOf: imagePath),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let detections: [DetectedTextRegion]
            do {
                detections = try detector.detectTextRegions(in: nsImage)
            } catch {
                print("Detection failed for \(imagePath.lastPathComponent): \(error)")
                continue
            }

            let boxes = detections.map(\.boundingBox)
            let overlapWarnings = reporter.detectOverlaps(in: boxes)

            // Lazy-init MangaOCRRecognizer (uses Bundle.main from host app)
            if mangaRecognizer == nil {
                let tokenizer = try MangaOCRTokenizer()
                mangaRecognizer = MangaOCRRecognizer(tokenizer: tokenizer)
            }

            var regions: [RegionResult] = []

            for (i, region) in detections.enumerated() {
                let regionWarnings = overlapWarnings.filter { $0.boxIndex == i }

                // MangaOCR: crop-based per-region recognition
                let mangaText: String
                do {
                    let (text, _) = try mangaRecognizer!.recognizeText(in: cgImage, region: region.boundingBox)
                    mangaText = text
                } catch {
                    mangaText = "[error]"
                }

                // VisionOCR: crop the region then run on the crop
                let visionText: String
                if let crop = cgImage.cropping(to: region.boundingBox) {
                    do {
                        let obs = try await visionOCR.recognizeText(in: crop)
                        visionText = obs.map(\.text).joined(separator: " ")
                    } catch {
                        visionText = "[error]"
                    }
                } else {
                    visionText = "[error]"
                }

                regions.append(RegionResult(
                    index: i,
                    rect: region.boundingBox,
                    mangaOCRText: mangaText,
                    visionOCRText: visionText,
                    overlapWarnings: regionWarnings
                ))
            }

            imageResults.append(ImageResult(imagePath: imagePath.lastPathComponent, regions: regions))
        }

        let result = BenchmarkResult(
            timestamp: Date(),
            imageCount: images.count,
            imageResults: imageResults
        )

        let report = reporter.generateReport(from: result)

        // Print to Xcode console for immediate viewing
        print("\n" + report + "\n")

        // Also attach to test result for history (Report Navigator ⌘9 → test run → testFullBenchmark)
        let attachment = XCTAttachment(string: report)
        attachment.name = "benchmark-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(imageResults.isEmpty, "Expected results for at least one image")
    }
}
