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
        // 23 example images × ~40 s/image + model load ≈ 15–20 min; default allowance is 10 min.
        executionTimeAllowance = 30 * 60

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

        // Require at least one reference string confirmed from Swift full-page inference on examples/book2.
        // Python verify.py produces different output than Swift for the same images (different quantization
        // path / mlx_vlm vs native MLX inference). book2/004 and book2/005 consistently produce clean text.
        let referenceStrings = ["どうしたんですか", "じゃあそれだけ", "仮説も", "転生したら", "第49話"]
        let allText = imageResults.compactMap { $0.unmatchedManga.first?.text }.joined(separator: " ")
        let hasMatch = referenceStrings.contains { allText.contains($0) }
        XCTAssert(hasMatch,
            "Expected at least one reference string \(referenceStrings) in PaddleOCR output. Got: \(allText.prefix(300))")
    }

    // MARK: - Smart-resize routing tests (task 15.4)

    func testSmartResizeSelectedForSmallCrop() {
        // 200×50 → 196×56 (56 patches); peak ≈ 56 × 1152 × 27 × 2 × 10 ≈ 34.8 MB — trivially within budget
        XCTAssertTrue(shouldUseSmartResize(
            srcW: 200, srcH: 50,
            patchSize: 14, hiddenSize: 1152, numLayers: 27,
            availableMemoryBytes: 8 * 1024 * 1024 * 1024
        ), "Small crop should use smart_resize path")
    }

    func testSmartResizeSelectedForLargeMangaPage() {
        // 1200×1800 clamped by max_pixels to ~812×1204 (86×58≈4988 patches)
        // MLX flash attention is O(N), not O(N²); peak ≈ 3.1 GB — within 8 GB threshold (6.4 GB)
        XCTAssertTrue(shouldUseSmartResize(
            srcW: 1200, srcH: 1800,
            patchSize: 14, hiddenSize: 1152, numLayers: 27,
            availableMemoryBytes: 8 * 1024 * 1024 * 1024
        ), "Large manga page should use smart_resize (clamped to max_pixels, flash attention)")
    }

    func testSmartResizeRespects80PercentThreshold() {
        // 56×28 → 8 patches; peak = 8 × 1152 × 27 × 2 × 10 ≈ 4.75 MB
        // With 5 MB budget (threshold 4 MB): 4.75 MB > 4 MB → tiling selected
        XCTAssertFalse(shouldUseSmartResize(
            srcW: 56, srcH: 28,
            patchSize: 14, hiddenSize: 1152, numLayers: 27,
            availableMemoryBytes: 5 * 1024 * 1024
        ), "Should fall back to tiling when estimated peak memory exceeds 80% threshold")
    }
    #endif
}
