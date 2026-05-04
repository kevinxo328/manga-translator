import XCTest
@testable import MangaTranslator
import AppKit

#if arch(arm64)
@testable import MangaTranslatorMLX
#endif

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

    #if arch(arm64)
    func testPaddleOCRBenchmark() async throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let modelDir = appSupport
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
            .appendingPathComponent("PaddleOCR-VL")
        
        // Use ModelDownloadService to find the actual model folder (it might be nested)
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelDir) else {
            print("PaddleOCR model not installed at \(modelDir.path) — skipping benchmark")
            return
        }

        print("Using PaddleOCR model at: \(resolvedDir.path)")
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        let images = scanner.findImages(in: examplesDir)
        
        guard !images.isEmpty else {
            print("No images in examples/ — skipping PaddleOCR benchmark")
            return
        }

        let clock = ContinuousClock()
        var imageResults: [ImageResult] = []

        for imagePath in images {
            guard let image = NSImage(contentsOf: imagePath),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let start = clock.now
            let result: (text: String, confidence: Float)
            do {
                result = try engine.infer(image: cgImage)
            } catch {
                print("PaddleOCR failed for \(imagePath.lastPathComponent): \(error)")
                continue
            }
            let elapsed = start.duration(to: clock.now)
            let durationMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15

            print("Image: \(imagePath.lastPathComponent), Latency: \(String(format: "%.2f", durationMs))ms, Text: [\(result.text)]")
            
            imageResults.append(ImageResult(
                imagePath: imagePath.path,
                pairedRegions: [], // Not using regions in this benchmark yet
                unmatchedManga: [BubbleCluster(boundingBox: .zero, text: result.text, observations: [])],
                unmatchedVision: []
            ))
        }

        let result = BenchmarkResult(
            timestamp: Date(),
            imageCount: imageResults.count,
            imageResults: imageResults
        )

        let report = reporter.generateReport(from: result)
        print("\n--- PaddleOCR Benchmark Report ---\n" + report + "\n")
        
        let attachment = XCTAttachment(string: report)
        attachment.name = "paddle-ocr-benchmark-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(imageResults.isEmpty, "Expected results for at least one image")
    }
    #endif
}
