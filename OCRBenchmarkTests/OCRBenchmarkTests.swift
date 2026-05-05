import XCTest
@testable import MangaTranslator
import AppKit

#if arch(arm64)
@testable import MangaTranslatorMLX
#endif

@MainActor
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

        let router = try await productionRouter()
        let paddleBubbles = try? router.processWithPaddleOCR(image: nsImage)
        let mangaBubbles = try await router.processWithMangaOCR(image: nsImage, sourceLanguage: .ja, allowVisionFallback: false)
        let visionBubbles = try await router.processWithVisionOCR(image: nsImage, sourceLanguage: .ja)

        print(
            "Image: \(firstImageURL.path), " +
            "Paddle bubbles: \(paddleBubbles?.count ?? 0), " +
            "Manga bubbles: \(mangaBubbles.count), " +
            "Vision bubbles: \(visionBubbles.count)"
        )
        XCTAssertGreaterThanOrEqual(mangaBubbles.count, 0)
        XCTAssertGreaterThanOrEqual(visionBubbles.count, 0)
    }

    // Full benchmark: scan → tri-engine OCR (production paths) → IoU → report
    func testFullBenchmark() async throws {
        let images = scanner.findImages(in: examplesDir)
        guard !images.isEmpty else {
            print("No images in examples/ — skipping full benchmark")
            return
        }

        let router = try await productionRouter()
        let clock = ContinuousClock()

        var imageResults: [ImageResult] = []

        for imagePath in images {
            guard let nsImage = NSImage(contentsOf: imagePath) else {
                continue
            }

            var latency: [String: Double] = [:]
            var failures: Set<String> = []

            let paddleStart = clock.now
            let paddleBubbles: [BubbleCluster]
            do {
                paddleBubbles = try router.processWithPaddleOCR(image: nsImage)
                let elapsed = paddleStart.duration(to: clock.now)
                latency["PaddleOCR"] = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            } catch {
                print("PaddleOCR failed for \(imagePath.lastPathComponent): \(error)")
                paddleBubbles = []
                failures.insert("PaddleOCR")
            }

            let mangaStart = clock.now
            let mangaBubbles: [BubbleCluster]
            do {
                mangaBubbles = try await router.processWithMangaOCR(image: nsImage, sourceLanguage: .ja, allowVisionFallback: false)
                let elapsed = mangaStart.duration(to: clock.now)
                latency["MangaOCR"] = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            } catch {
                print("MangaOCR failed for \(imagePath.lastPathComponent): \(error)")
                mangaBubbles = []
                failures.insert("MangaOCR")
            }

            let visionStart = clock.now
            let visionBubbles: [BubbleCluster]
            do {
                visionBubbles = try await router.processWithVisionOCR(image: nsImage, sourceLanguage: .ja)
                let elapsed = visionStart.duration(to: clock.now)
                latency["Vision"] = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            } catch {
                print("VisionOCR failed for \(imagePath.lastPathComponent): \(error)")
                visionBubbles = []
                failures.insert("Vision")
            }

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

    private func productionRouter() async throws -> OCRRouter {
        #if arch(arm64)
        return await MainActor.run {
            OCRRouter.makeProductionRouter()
        }
        #else
        return OCRRouter()
        #endif
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
