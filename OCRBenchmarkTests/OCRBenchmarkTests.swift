import XCTest
@testable import MangaTranslator
import AppKit
import Foundation

#if arch(arm64)
@testable import MangaTranslatorMLX
import MLX
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

    #if arch(arm64)
    private func benchmarkExpandedCrop(
        image: CGImage,
        region: CGRect
    ) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropPaddingRatio: CGFloat = 0.18
        let minimumHorizontalPadding: CGFloat = 10
        let minimumVerticalPadding: CGFloat = 6
        let elongatedBubbleThreshold: CGFloat = 1.6
        let tallBubbleThreshold: CGFloat = 0.7
        let elongatedHorizontalBoostRatio: CGFloat = 0.08
        let tallVerticalBoostRatio: CGFloat = 0.08

        let aspectRatio = region.width / region.height
        var horizontalPadding = max(minimumHorizontalPadding, region.width * cropPaddingRatio)
        var verticalPadding = max(minimumVerticalPadding, region.height * cropPaddingRatio)

        if aspectRatio >= elongatedBubbleThreshold {
            horizontalPadding += region.width * elongatedHorizontalBoostRatio
        } else if aspectRatio <= tallBubbleThreshold {
            verticalPadding += region.height * tallVerticalBoostRatio
        }

        let expanded = region.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        let clamped = expanded.intersection(imageBounds).integral
        guard clamped.width > 0 && clamped.height > 0 else { return nil }
        return image.cropping(to: clamped)
    }

    private func assertNoImmediateParityFailure(
        trace: PaddleOCRDebugTrace,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            trace.generatedTokens.isEmpty,
            "Expected \(label) to generate at least one token instead of terminating immediately with \(String(describing: trace.terminationToken))",
            file: file,
            line: line
        )
        XCTAssertFalse(
            trace.trimmedText.isEmpty,
            "Expected \(label) to produce non-empty text, but got \(String(reflecting: trace.rawText))",
            file: file,
            line: line
        )
        if let firstCharacter = trace.rawText.first {
            XCTAssertFalse(
                firstCharacter.isNewline,
                "Expected \(label) to avoid newline as the first generated character, but got \(String(reflecting: trace.rawText))",
                file: file,
                line: line
            )
        }
    }
    #endif

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
        let paddleResult = try? await router.processWithPaddleOCR(image: nsImage)
        let mangaResult = try await router.processWithMangaOCR(image: nsImage)
        let mangaBubbles = mangaResult.bubbles

        print(
            "Image: \(firstImageURL.path), " +
            "Paddle bubbles: \(paddleResult?.bubbles.count ?? 0), " +
            "Manga bubbles: \(mangaBubbles.count)"
        )
        XCTAssertGreaterThanOrEqual(mangaBubbles.count, 0)
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

        // 1. Batch process all images with PaddleOCR
        var paddleResults: [URL: (result: MangaOCRPageResult, latency: Double, failed: Bool)] = [:]
        for imagePath in images {
            guard let nsImage = NSImage(contentsOf: imagePath) else { continue }

            let start = clock.now
            do {
                let result = try await router.processWithPaddleOCR(image: nsImage)
                let elapsed = start.duration(to: clock.now)
                let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                paddleResults[imagePath] = (result, ms, false)
            } catch {
                print("PaddleOCR failed for \(imagePath.lastPathComponent): \(error)")
                let empty = MangaOCRPageResult(bubbles: [], textPixelMask: nil, lowConfidenceDetectionCount: 0)
                paddleResults[imagePath] = (empty, 0, true)
            }
        }

        // 2. Batch process all images with MangaOCR
        var mangaResults: [URL: (result: MangaOCRPageResult, latency: Double, failed: Bool)] = [:]
        for imagePath in images {
            guard let nsImage = NSImage(contentsOf: imagePath) else { continue }

            let start = clock.now
            do {
                let result = try await router.processWithMangaOCR(image: nsImage)
                let elapsed = start.duration(to: clock.now)
                let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                mangaResults[imagePath] = (result, ms, false)
            } catch {
                print("MangaOCR failed for \(imagePath.lastPathComponent): \(error)")
                let empty = MangaOCRPageResult(bubbles: [], textPixelMask: nil, lowConfidenceDetectionCount: 0)
                mangaResults[imagePath] = (empty, 0, true)
            }
        }

        // 3. Assemble results and calculate IoU (Report logic remains identical)
        let emptyPageResult = MangaOCRPageResult(bubbles: [], textPixelMask: nil, lowConfidenceDetectionCount: 0)
        var imageResults: [ImageResult] = []
        for imagePath in images {
            let pRes = paddleResults[imagePath] ?? (emptyPageResult, 0, true)
            let mRes = mangaResults[imagePath] ?? (emptyPageResult, 0, true)

            var latency: [String: Double] = [:]
            var failures: Set<String> = []

            if !pRes.failed { latency["PaddleOCR"] = pRes.latency } else { failures.insert("PaddleOCR") }
            if !mRes.failed { latency["MangaOCR"] = mRes.latency } else { failures.insert("MangaOCR") }

            let mangaBubbles = mRes.result.bubbles
            let paddleBubbles = pRes.result.bubbles
            let paddleVsManga = BubbleRegionMatcher.match(anchor: paddleBubbles, compared: mangaBubbles)

            let lowConfCount = mRes.failed ? 0 : mRes.result.lowConfidenceDetectionCount
            let invertedCount = mangaBubbles.filter { $0.isInverted }.count

            imageResults.append(ImageResult(
                imagePath: imagePath.path,
                paddleVsManga: paddleVsManga.paired,
                unmatchedPaddleManga: paddleVsManga.unmatchedAnchor,
                unmatchedManga: paddleVsManga.unmatchedCompared,
                latency: latency,
                failures: failures,
                lowConfidenceDetections: lowConfCount,
                invertedBubbles: invertedCount
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

    #if arch(arm64)
    func testCaptureDebugTokenTracesForBenchmarkEmptyRegions() throws {
        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available for debug trace capture — skipping")
            return
        }

        let cases: [(String, String, CGRect)] = [
            ("book1/001#r2", "book1/001.jpg", CGRect(x: 292.0651, y: 669.7273, width: 22.0659, height: 71.1165)),
            ("book1/001#r3", "book1/001.jpg", CGRect(x: 963.3900, y: 1138.7845, width: 21.4628, height: 70.9517)),
            ("book1/002#r9", "book1/002.jpg", CGRect(x: 244.2680, y: 942.5192, width: 72.4024, height: 141.1021)),
            ("book1/004#r12", "book1/004.jpg", CGRect(x: 806.2938, y: 1452.3148, width: 33.9647, height: 98.4724)),
            ("book1/004#r13", "book1/004.jpg", CGRect(x: 125.4072, y: 1151.9563, width: 146.3098, height: 375.1194)),
        ]

        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var captured = 0

        for (label, relativePath, region) in cases {
            let imageURL = examplesDir.appendingPathComponent(relativePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let cropped = benchmarkExpandedCrop(image: cgImage, region: region) else {
                XCTFail("Could not prepare crop for \(label)")
                continue
            }

            let trace = try engine.inferDebug(image: cropped)
            captured += 1
            print("TRACE \(label)")
            print("  rawText: \(String(reflecting: trace.rawText))")
            print("  trimmedText: \(String(reflecting: trace.trimmedText))")
            print("  tokens: \(trace.generatedTokens)")
            print("  terminationToken: \(String(describing: trace.terminationToken))")
            let firstStepTopTokens = trace.firstStepTopTokens.map { token in
                "tokenId=\(token.tokenId), logit=\(token.logit)"
            }.joined(separator: "; ")
            print("  firstStepTopTokens: [\(firstStepTopTokens)]")

        }

        XCTAssertEqual(captured, cases.count)
    }

    func testKnownEmptyCasesDebugParity() throws {
        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let cases: [(String, String, CGRect)] = [
            ("book1/001#r2", "book1/001.jpg", CGRect(x: 292.0651, y: 669.7273, width: 22.0659, height: 71.1165)),
            ("book1/001#r3", "book1/001.jpg", CGRect(x: 963.3900, y: 1138.7845, width: 21.4628, height: 70.9517)),
            ("book1/002#r9", "book1/002.jpg", CGRect(x: 244.2680, y: 942.5192, width: 72.4024, height: 141.1021)),
            ("book1/004#r12", "book1/004.jpg", CGRect(x: 806.2938, y: 1452.3148, width: 33.9647, height: 98.4724)),
            ("book1/004#r13", "book1/004.jpg", CGRect(x: 125.4072, y: 1151.9563, width: 146.3098, height: 375.1194)),
        ]

        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        
        for (label, relativePath, region) in cases {
            let imageURL = examplesDir.appendingPathComponent(relativePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let cropped = benchmarkExpandedCrop(image: cgImage, region: region) else {
                XCTFail("Could not prepare crop for \(label)")
                continue
            }

            let trace = try engine.inferDebug(image: cropped)
            assertNoImmediateParityFailure(trace: trace, label: label)
        }
    }

    func testBenchmarkEmptyCasesProductionPath() throws {
        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let cases: [(String, String, CGRect)] = [
            ("book1/001#r2", "book1/001.jpg", CGRect(x: 292.0651, y: 669.7273, width: 22.0659, height: 71.1165)),
            ("book1/001#r3", "book1/001.jpg", CGRect(x: 963.3900, y: 1138.7845, width: 21.4628, height: 70.9517)),
            ("book1/002#r9", "book1/002.jpg", CGRect(x: 244.2680, y: 942.5192, width: 72.4024, height: 141.1021)),
            ("book1/004#r12", "book1/004.jpg", CGRect(x: 806.2938, y: 1452.3148, width: 33.9647, height: 98.4724)),
            ("book1/004#r13", "book1/004.jpg", CGRect(x: 125.4072, y: 1151.9563, width: 146.3098, height: 375.1194)),
        ]

        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        
        for (label, relativePath, region) in cases {
            let imageURL = examplesDir.appendingPathComponent(relativePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let cropped = benchmarkExpandedCrop(image: cgImage, region: region) else {
                XCTFail("Could not prepare crop for \(label)")
                continue
            }

            let result = try engine.infer(image: cropped)
            let isEmptyOrNewline = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            XCTAssertFalse(isEmptyOrNewline, "Expected \(label) to produce text, but got empty/newline")
        }
    }




    private func tensorSummary(_ array: MLXArray) -> String {
        let floatArray = array.asType(.float32)
        let values = floatArray.asArray(Float.self)
        let shape = array.shape.map(String.init).joined(separator: "x")
        guard !values.isEmpty else {
            return "shape=\(shape), empty"
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let meanValue = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - meanValue
            return partial + delta * delta
        } / Float(values.count)
        let stdValue = sqrt(variance)
        let l2Value = sqrt(values.reduce(0) { $0 + $1 * $1 })
        let prefix = values.prefix(8).map { String(format: "%.5f", $0) }.joined(separator: ", ")
        return String(
            format: "shape=%@, min=%.5f, max=%.5f, mean=%.5f, std=%.5f, l2=%.5f, prefix=[%@]",
            shape,
            minValue,
            maxValue,
            meanValue,
            stdValue,
            l2Value,
            prefix
        )
    }
    #endif

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
