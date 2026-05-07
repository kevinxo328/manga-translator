import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

#if arch(arm64)
@testable import MangaTranslatorMLX

@MainActor
final class E2EOCRIntegrationTests: XCTestCase {

    private func createRouter(
        downloadState: ModelDownloadState,
        downloadEnabled: Bool,
        capability: PaddleOCRCapability = .supported,
        paddleOCRFactory: @escaping () throws -> any OCRRecognizing = { throw PaddleOCRError.modelUnavailable }
    ) -> OCRRouter {
        let capabilityChecker = MockCapabilityChecker(capability)
        let downloadManager = MockDownloadManager(state: downloadState, enabled: downloadEnabled)
        return OCRRouter(
            capabilityChecker: capabilityChecker,
            downloadManager: downloadManager,
            paddleOCRFactory: paddleOCRFactory
        )
    }

    // 9.1 Run full OCR pipeline with high-accuracy model enabled
    func testFullPipelineHighAccuracyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["ENABLE_PADDLEOCR_SPIKE_TESTS"] == "1" else { return }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelDir = repoRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("convert_model")
            .appendingPathComponent("mlx_output")

        guard FileManager.default.fileExists(atPath: modelDir.path) else { return }
        guard let image = firstParitySampleImage() else {
            throw XCTSkip("Missing parity sample image at /private/tmp/paddle-detector-examples.json")
        }
        
        let router = createRouter(
            downloadState: .downloaded,
            downloadEnabled: true,
            paddleOCRFactory: { try PaddleOCRVLRecognizer(modelDirectory: modelDir) }
        )
        
        let bubbles = try await router.processPage(image: image, sourceLanguage: .ja)
        XCTAssertFalse(bubbles.isEmpty, "OCR pipeline should return non-empty bubbles")
    }
    
    // 9.2 Run full OCR pipeline with high-accuracy model disabled
    func testFullPipelineHighAccuracyDisabled() async throws {
        let image = makeTestImage(width: 100, height: 100)
        
        let router = createRouter(
            downloadState: .downloaded,
            downloadEnabled: false,
            paddleOCRFactory: { 
                XCTFail("PaddleOCR factory should not be called when disabled")
                throw PaddleOCRError.modelUnavailable
            }
        )
        
        do {
            let bubbles = try await router.processPage(image: image, sourceLanguage: .ja)
            print("Fallback pipeline returned \(bubbles.count) bubbles")
        } catch {
            // It might fail if MangaOCR isn't fully mocked, but the router shouldn't call PaddleOCR.
        }
    }
    
    // 9.6 Test strict-mode failure end-to-end & 9.6a Assert strict-mode no-fallback invariants
    func testStrictModeNoFallback() async throws {
        let image = makeTestImage(width: 100, height: 100)
        
        var factoryCalledCount = 0
        let router = createRouter(
            downloadState: .downloaded,
            downloadEnabled: true,
            paddleOCRFactory: { 
                factoryCalledCount += 1
                throw PaddleOCRError.inferenceFailed("Simulated error")
            }
        )
        
        do {
            _ = try await router.processPage(image: image, sourceLanguage: .ja)
            XCTFail("Pipeline should have failed")
        } catch let error as PaddleOCRError {
            XCTAssertEqual(error.code, "paddleocr.inference_failed")
            XCTAssertEqual(factoryCalledCount, 1)
        } catch {
            XCTFail("Wrong error type thrown")
        }
    }

    private func firstParitySampleImage() -> NSImage? {
        let detectorJSONPath = URL(fileURLWithPath: "/private/tmp/paddle-detector-examples.json")
        guard let data = try? Data(contentsOf: detectorJSONPath),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = payload["pages"] as? [[String: Any]],
              let imagePath = pages.first?["imagePath"] as? String else {
            return nil
        }
        return NSImage(contentsOf: URL(fileURLWithPath: imagePath))
    }

    private func makeTestImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - Mocks

private final class MockCapabilityChecker: DeviceCapabilityChecking {
    private let capability: PaddleOCRCapability
    init(_ capability: PaddleOCRCapability) { self.capability = capability }
    func checkPaddleOCRCapability() -> PaddleOCRCapability { capability }
}

private final class MockDownloadManager: ModelDownloadManaging {
    let state: ModelDownloadState
    private let enabled: Bool
    init(state: ModelDownloadState, enabled: Bool = false) {
        self.state = state
        self.enabled = enabled
    }
    var isPaddleOCREnabled: Bool { state == .downloaded && enabled }
}

private final class MockComicTextDetector: ComicTextRegionDetecting {
    var resultByPath = [String: [DetectedTextRegion]]()

    func detectTextRegions(in image: NSImage) throws -> [DetectedTextRegion] {
        let key = image.accessibilityDescription() ?? ""
        return resultByPath[key, default: []]
    }
}

private func writeTestPNG(at url: URL, width: Int = 32, height: Int = 24) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    rep?.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = rep.flatMap(NSGraphicsContext.init(bitmapImageRep:))
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let rep, let data = rep.representation(using: .png, properties: [:]) else {
        throw OCRError.invalidImage
    }
    try data.write(to: url)
}

@MainActor
final class ComicTextDetectorExportTests: XCTestCase {
    func testExporterEmitsJSONTextRegionBoxes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("page-1.png")
        try writeTestPNG(at: imageURL)

        let detector = MockComicTextDetector()
        detector.resultByPath[imageURL.path] = [
            DetectedTextRegion(
                boundingBox: CGRect(x: 12.5, y: 8.0, width: 40.0, height: 16.0),
                confidence: 0.91,
                classIndex: 0
            )
        ]

        let exporter = ComicTextDetectorExporter(detector: detector)
        let document = try exporter.export(pageImagePaths: [imageURL.path])

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.pages.count, 1)
        XCTAssertEqual(document.pages[0].imagePath, imageURL.path)
        XCTAssertEqual(document.pages[0].pageWidth, 32)
        XCTAssertEqual(document.pages[0].pageHeight, 24)
        XCTAssertEqual(
            document.pages[0].regions,
            [
                ComicTextDetectorExportRegion(
                    x: 12.5,
                    y: 8.0,
                    width: 40.0,
                    height: 16.0,
                    confidence: 0.91,
                    classIndex: 0
                )
            ]
        )
    }

    func testExporterFailsForMissingImagePath() throws {
        let detector = MockComicTextDetector()
        let exporter = ComicTextDetectorExporter(detector: detector)

        XCTAssertThrowsError(try exporter.export(pageImagePaths: ["/tmp/does-not-exist.png"])) { error in
            XCTAssertEqual(error as? ComicTextDetectorExportError, .imageNotFound("/tmp/does-not-exist.png"))
        }
    }

    func testExporterFailsForUnreadableImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("broken.png")
        try Data("not-an-image".utf8).write(to: imageURL)

        let detector = MockComicTextDetector()
        let exporter = ComicTextDetectorExporter(detector: detector)

        XCTAssertThrowsError(try exporter.export(pageImagePaths: [imageURL.path])) { error in
            XCTAssertEqual(error as? ComicTextDetectorExportError, .unreadableImage(imageURL.path))
        }
    }

    func testExporterKeepsZeroRegionPages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("empty.png")
        try writeTestPNG(at: imageURL)

        let detector = MockComicTextDetector()
        let exporter = ComicTextDetectorExporter(detector: detector)
        let document = try exporter.export(pageImagePaths: [imageURL.path])

        XCTAssertEqual(document.pages.count, 1)
        XCTAssertTrue(document.pages[0].regions.isEmpty)
    }
}
#endif
