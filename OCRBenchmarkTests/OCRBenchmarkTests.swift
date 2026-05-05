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

    // Integration test: full pipeline on a single known test image
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
        let visionObservations = try await visionService.recognizeText(in: nsImage, sourceLanguage: .ja)
        let visionBubbles = bubbleDetector.detectBubbles(from: visionObservations)

        // For this test, we just check that matching still works for existing engines
        let result = BubbleRegionMatcher.match(anchor: mangaBubbles, compared: visionBubbles)
        print("Image: \(firstImageURL.path), Manga bubbles: \(mangaBubbles.count), Vision bubbles: \(visionBubbles.count), Paired: \(result.paired.count)")
    }

    // Full benchmark: scan → tri-engine OCR (production paths) → IoU → report
    func testFullBenchmark() async throws {
        let images = scanner.findImages(in: examplesDir)
        guard !images.isEmpty else {
            print("No images in examples/ — skipping full benchmark")
            return
        }

        let mangaService = MangaOCRService()
        let visionService = VisionOCRService()
        let bubbleDetector = BubbleDetector()
        let clock = ContinuousClock()

        // Mock capability and download to force PaddleOCR path in router
        struct MockCapability: DeviceCapabilityChecking {
            func checkPaddleOCRCapability() -> PaddleOCRCapability { .supported }
        }
        
        @MainActor
        class MockDownload: ModelDownloadManaging {
            var state: ModelDownloadState = .downloaded
            var isPaddleOCREnabled: Bool = true
        }

        let downloadManager = await MainActor.run { MockDownload() }
        let router = OCRRouter(
            mangaOCRService: mangaService,
            visionOCRService: visionService,
            capabilityChecker: MockCapability(),
            downloadManager: downloadManager,
            paddleOCRFactory: {
                #if arch(arm64)
                throw PaddleOCRError.modelUnavailable
                #else
                throw PaddleOCRError.modelUnavailable
                #endif
            }
        )

        var imageResults: [ImageResult] = []

        for imagePath in images {
            guard let nsImage = NSImage(contentsOf: imagePath) else {
                continue
            }

            var latency: [String: Double] = [:]
            var failures: Set<String> = []

            // 1. PaddleOCR Path (via OCRRouter)
            let paddleBubbles: [BubbleCluster]
            let paddleStart = clock.now
            do {
                paddleBubbles = try await router.processPage(image: nsImage, sourceLanguage: .ja)
                let elapsed = paddleStart.duration(to: clock.now)
                latency["PaddleOCR"] = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            } catch {
                print("PaddleOCR failed for \(imagePath.lastPathComponent): \(error)")
                paddleBubbles = []
                failures.insert("PaddleOCR")
            }

            // 2. MangaOCR Path (direct bypass)
            let mangaStart = clock.now
            let mangaBubbles: [BubbleCluster]
            do {
                mangaBubbles = try mangaService.recognizeAndCluster(in: nsImage)
                let elapsed = mangaStart.duration(to: clock.now)
                latency["MangaOCR"] = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            } catch {
                print("MangaOCR failed for \(imagePath.lastPathComponent): \(error)")
                mangaBubbles = []
                failures.insert("MangaOCR")
            }

            // 3. Vision Path
            let visionStart = clock.now
            let visionBubbles: [BubbleCluster]
            do {
                let obs = try await visionService.recognizeText(in: nsImage, sourceLanguage: .ja)
                visionBubbles = bubbleDetector.detectBubbles(from: obs)
                let elapsed = visionStart.duration(to: clock.now)
                latency["Vision"] = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            } catch {
                print("VisionOCR failed for \(imagePath.lastPathComponent): \(error)")
                visionBubbles = []
                failures.insert("Vision")
            }

            // Matching
            let paddleVsManga = BubbleRegionMatcher.match(anchor: paddleBubbles, compared: mangaBubbles)
            let paddleVsVision = BubbleRegionMatcher.match(anchor: paddleBubbles, compared: visionBubbles)
            
            imageResults.append(ImageResult(
                imagePath: imagePath.path,
                paddleVsManga: paddleVsManga.paired,
                paddleVsVision: paddleVsVision.paired,
                unmatchedPaddleManga: paddleVsManga.unmatchedAnchor,
                unmatchedPaddleVision: paddleVsVision.unmatchedAnchor,
                unmatchedManga: paddleVsManga.unmatchedCompared,
                unmatchedVision: paddleVsVision.unmatchedCompared,
                latency: latency,
                failures: failures
            ))
        }

        let result = BenchmarkResult(
            timestamp: Date(),
            imageCount: images.count,
            imageResults: imageResults
        )

        let report = reporter.generateReport(from: result)

        print("\n" + report + "\n")

        let attachment = XCTAttachment(string: report)
        attachment.name = "benchmark-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(imageResults.isEmpty, "Expected results for at least one image")
    }

    // MARK: - Smart-resize routing tests

    #if arch(arm64)
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
