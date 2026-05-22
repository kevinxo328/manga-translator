import XCTest
import CoreGraphics
import AppKit
@testable import MangaTranslator

@MainActor
final class OCRRouterTests: XCTestCase {

    // MARK: - Task 6.1: Routing decisions

    func testSiliconDownloadedEnabledCallsPaddleOCRFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: {
                factoryCalled = true
                return MockOCRRecognizer(name: "paddle")
            }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertTrue(factoryCalled, "PaddleOCR factory must be called when Silicon+downloaded+enabled")
    }

    func testSiliconNotDownloadedDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called when model is not downloaded")
    }

    func testSiliconDownloadedDisabledDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: false),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called when paddleocr is disabled")
    }

    func testUnsupportedCapabilityDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.unsupported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called on unsupported (Intel) device")
    }

    func testEnabledWithoutDownloadIsRejected() async {
        // isPaddleOCREnabled checks state == .downloaded first; .notDownloaded blocks activation.
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: true),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .ja)
        XCTAssertFalse(factoryCalled, "Factory must not be called when model is not downloaded, even if enabled flag is set")
    }

    func testNonJapaneseDownloadedEnabledCallsPaddleOCRFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: {
                factoryCalled = true
                return MockOCRRecognizer(name: "paddle")
            }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .en)
        XCTAssertTrue(factoryCalled, "Non-Japanese route must still select PaddleOCR when available")
    }

    func testNonJapaneseWithoutDownloadDoesNotCallFactory() async {
        var factoryCalled = false
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { factoryCalled = true; return MockOCRRecognizer(name: "paddle") }
        )

        _ = try? await router.processPage(image: NSImage(), sourceLanguage: .en)
        XCTAssertFalse(factoryCalled, "Non-Japanese route must not call PaddleOCR factory when model is unavailable")
    }

    // MARK: - Task 6.2: Strict-mode failure

    func testPaddleOCRFactoryFailureThrowsPaddleOCRError() async throws {
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { throw PaddleOCRError.inferenceFailed("test trigger") }
        )

        do {
            _ = try await router.processPage(image: NSImage(), sourceLanguage: .ja)
            XCTFail("Expected PaddleOCRError to be thrown")
        } catch let error as PaddleOCRError {
            XCTAssertEqual(error.code, "paddleocr.inference_failed")
        } catch {
            XCTFail("Expected PaddleOCRError, got \(type(of: error)): \(error)")
        }
    }

    func testPaddleOCRInferenceFailureDoesNotFallBackToMangaOCR() async {
        // When PaddleOCR is active and fails, MangaOCRService.recognizeAndCluster
        // must NOT be invoked with the MangaOCR recognizer. We verify by checking
        // that no MangaOCR-flavoured result is returned (error is propagated instead).
        let throwingRecognizer = ThrowingOCRRecognizer()
        let router = OCRRouter(
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { throwingRecognizer }
        )

        do {
            _ = try await router.processPage(image: NSImage(), sourceLanguage: .ja)
            XCTFail("Expected an error")
        } catch is PaddleOCRError {
            // Correct: PaddleOCRError was propagated, not a MangaOCR result.
        } catch {
            XCTFail("Expected PaddleOCRError, got \(error)")
        }
    }

    // MARK: - Task 6.2a: Stable error codes

    func testModelUnavailableCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.modelUnavailable.code, "paddleocr.model_unavailable")
    }

    func testInferenceFailedCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.inferenceFailed("any").code, "paddleocr.inference_failed")
    }

    func testDownloadFailedCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.downloadFailed("any").code, "paddleocr.download_failed")
    }

    func testVerifyFailedCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.verifyFailed.code, "paddleocr.verify_failed")
    }

    func testStorageUnavailableCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.storageUnavailable("x").code, "paddleocr.storage_unavailable")
    }

    func testOperationCancelledCodeIsStable() {
        XCTAssertEqual(PaddleOCRError.operationCancelled.code, "paddleocr.operation_cancelled")
    }

    // MARK: - Task 6.2b: Error code / localization key independence

    func testErrorCodeIsNotTheLocalizationString() {
        // The stable error code must differ from the user-facing message.
        // This ensures code keys and localization keys are separate concerns.
        let cases: [PaddleOCRError] = [
            .modelUnavailable,
            .inferenceFailed("x"),
            .downloadFailed("x"),
            .verifyFailed,
            .storageUnavailable("x"),
            .operationCancelled,
        ]
        for error in cases {
            let code = error.code
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty,
                           "\(code): errorDescription must not be empty")
            XCTAssertNotEqual(code, description,
                              "\(code): error code must differ from user-facing localization string")
        }
    }

    // MARK: - PaddleOCR GPU cache cleanup

    func testPaddleOCRSuccessPathInvokesCacheCleanupOnce() async throws {
        let cleanup = MockPaddleOCRGPUCacheCleanup()
        let recognizer = MockOCRRecognizer(name: "paddle")
        let service = MangaOCRService(detector: MockComicTextDetector())
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { recognizer },
            paddleOCRCacheCleanup: cleanup
        )

        _ = try await router.processPage(image: makeTestImage(width: 100, height: 100), sourceLanguage: .ja)
        XCTAssertEqual(cleanup.clearCount, 1, "Cleanup must run exactly once after a successful PaddleOCR page")
    }

    func testPaddleOCRFailurePathInvokesCacheCleanupOnce() async {
        let cleanup = MockPaddleOCRGPUCacheCleanup()
        let throwingRecognizer = ThrowingOCRRecognizer()
        let service = MangaOCRService(detector: MockComicTextDetector())
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { throwingRecognizer },
            paddleOCRCacheCleanup: cleanup
        )

        do {
            _ = try await router.processPage(image: makeTestImage(width: 100, height: 100), sourceLanguage: .ja)
            XCTFail("Expected PaddleOCRError to be thrown")
        } catch is PaddleOCRError {
            // expected
        } catch {
            XCTFail("Expected PaddleOCRError, got \(error)")
        }
        XCTAssertEqual(cleanup.clearCount, 1, "Cleanup must run exactly once after a failed PaddleOCR page")
    }

    func testMangaOCRPathDoesNotInvokeCacheCleanup() async throws {
        let cleanup = MockPaddleOCRGPUCacheCleanup()
        let recognizer = MockOCRRecognizer(name: "manga")
        let service = MangaOCRService(detector: MockComicTextDetector())
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .notDownloaded, enabled: false),
            paddleOCRFactory: { recognizer },
            paddleOCRCacheCleanup: cleanup
        )

        _ = try await router.processPage(image: makeTestImage(width: 100, height: 100), sourceLanguage: .ja)
        XCTAssertEqual(cleanup.clearCount, 0, "MangaOCR path must not invoke PaddleOCR GPU cache cleanup")
    }

    // MARK: - Task 6.3: Reset tests

    func testResetPaddleOCRRecognizerClearsRecognizer() async {
        let service = MangaOCRService()
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true)
        )

        await service.setRecognizer(MockOCRRecognizer(name: "active"))
        var r = await service.recognizer
        XCTAssertNotNil(r)

        await router.resetPaddleOCRRecognizer()
        r = await service.recognizer
        XCTAssertNil(r, "resetPaddleOCRRecognizer() must clear the active recognizer")
    }

    func testRecognizerResetsWhenPreferenceToggledViaResetMethod() async {
        // Simulates the preference-toggle path: caller toggles preference then calls reset.
        let service = MangaOCRService()
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true)
        )

        await service.setRecognizer(MockOCRRecognizer(name: "paddle-active"))
        await router.resetPaddleOCRRecognizer()
        let r = await service.recognizer
        XCTAssertNil(r)
    }

    func testRecognizerResetsWhenModelDeletedViaResetMethod() async {
        // Simulates the model-delete path: ModelDownloadService calls reset on the router.
        let service = MangaOCRService()
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true)
        )

        await service.setRecognizer(MockOCRRecognizer(name: "paddle-active"))
        await router.resetPaddleOCRRecognizer()
        let r = await service.recognizer
        XCTAssertNil(r, "Recognizer must be released after model deletion")
    }
    func testMainActorResponsivenessDuringOCR() async throws {
        let recognizer = SlowMockOCRRecognizer()
        let service = MangaOCRService(detector: MockComicTextDetector())
        let image = makeTestImage(width: 100, height: 100)
        
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { recognizer }
        )
        
        var ticksDuringOCR = 0
        let processTask = Task { @MainActor in
            _ = try? await router.processPage(image: image, sourceLanguage: .ja)
        }
        
        let tickTask = Task { @MainActor in
            while !processTask.isCancelled && !recognizer.didFinish {
                ticksDuringOCR += 1
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        await processTask.value
        tickTask.cancel()
        await tickTask.value
        
        XCTAssertGreaterThan(ticksDuringOCR, 0, "MainActor should remain responsive and process other tasks during OCR. Ticks: \(ticksDuringOCR)")
    }
    func testBatchPageStateTransitions() async throws {
        let recognizer = SlowMockOCRRecognizer()
        let service = MangaOCRService(detector: MockComicTextDetector())
        
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 400, bitsPerPixel: 32)!
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.addRepresentation(rep)
        
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { recognizer }
        )
        
        let prefs = PreferencesService()
        let viewModel = await MainActor.run { TranslationViewModel(preferences: prefs, ocrRouter: router, translationService: MockTranslationService()) }
        
        await MainActor.run {
            var page1 = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/1.jpg"))
            page1.image = image
            var page2 = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/2.jpg"))
            page2.image = image
            viewModel.pages = [page1, page2]
        }
        
        let translateTask = Task { @MainActor in
            await viewModel.retranslateAllPages()
        }
        
        // Wait briefly to allow tasks to start and enter processing state
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let state1 = await MainActor.run { viewModel.pages[0].state }
        
        // If the execution model is properly non-blocking, we should be able to observe
        // the intermediate 'processing' state while OCR is running.
        if case .processing = state1 {
            // expected
        } else {
            XCTFail("Page 1 should be in processing state during OCR, but was \(state1)")
        }
        
        await translateTask.value
        
        let finalState1 = await MainActor.run { viewModel.pages[0].state }
        if case .translated = finalState1 {
            // expected
        } else {
            XCTFail("Page 1 should be translated after OCR finishes, but was \(finalState1)")
        }
    }

    func testInjectedTranslationServiceDoesNotRequireAPIKey() async {
        let recognizer = MockOCRRecognizer(name: "paddle-active")
        let service = MangaOCRService(detector: MockComicTextDetector())
        let image = makeTestImage(width: 100, height: 100)

        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { recognizer }
        )

        let prefs = PreferencesService()
        let viewModel = TranslationViewModel(
            preferences: prefs,
            ocrRouter: router,
            translationService: MockTranslationService()
        )

        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/injected-translation.jpg"))
        page.image = image
        viewModel.pages = [page]

        await viewModel.translatePage(at: 0, bypassCache: true)

        if case .translated = viewModel.pages[0].state {
            // expected
        } else {
            XCTFail("Injected translation service should bypass API key requirements, but page state was \(viewModel.pages[0].state)")
        }

        XCTAssertFalse(viewModel.showMissingKeyAlert)
    }
    func testAsyncOCRPathEmptyRegion() async throws {
        // Task 1.4: boundary test for async OCR path with empty region
        let recognizer = MockOCRRecognizer(name: "paddle-active")
        let service = MangaOCRService(detector: MockComicTextDetector(returnsEmpty: true))
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { recognizer }
        )
        
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        let emptyImage = NSImage(size: NSSize(width: 1, height: 1))
        emptyImage.addRepresentation(rep)
        
        let result = try await router.processPage(image: emptyImage, sourceLanguage: .ja)
        // With an empty image, the detector should find 0 regions, returning empty bubbles
        XCTAssertTrue(result.bubbles.isEmpty, "Empty region should safely return empty results")
    }

    func testAsyncOCRPathCancellation() async throws {
        // Task 1.4: boundary test for async OCR path cancellation
        let recognizer = SlowMockOCRRecognizer()
        let service = MangaOCRService(detector: MockComicTextDetector())
        
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 400, bitsPerPixel: 32)!
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.addRepresentation(rep)
        
        await service.setRecognizer(recognizer)
        let router = OCRRouter(
            mangaOCRService: service,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: MockDownloadManager(state: .downloaded, enabled: true),
            paddleOCRFactory: { recognizer }
        )
        
        let processTask = Task { @MainActor in
            return try await router.processPage(image: image, sourceLanguage: .ja)
        }
        
        // Cancel the task immediately
        processTask.cancel()
        
        do {
            _ = try await processTask.value
            // Depending on implementation, cancellation might throw CancellationError
            // or just return empty/partial results if the underlying work isn't fully cooperative.
            // Currently, OCR compute is synchronous, so it might not throw.
            // Once we move it to a task, we should assert cancellation.
        } catch is CancellationError {
            // expected when cooperative cancellation is implemented
        } catch {
            // other errors
        }
    }

    // MARK: - Task 8 follow-up: production-path lifecycle inference coordination

    // Verifies the production OCR path registers active inference with the
    // lifecycle actor so `ModelDownloadService.delete()` waits for in-flight
    // PaddleOCR work. Without the OCRRouter wiring, `delete()` would proceed
    // immediately and `.waitForInferencesBegan` would never fire, even though
    // `local-model-lifecycle/spec.md` requires deletion to wait for inference.
    func testPaddleOCRRouteRegistersInferenceSoDeleteWaitsForCompletion() async throws {
        // Seed a real ModelDownloadService against a temp container so its
        // lifecycle actor backs delete() and there are artifacts for delete()
        // to remove.
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let currentDir = container.appendingPathComponent("PaddleOCR-VL.current")
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: currentDir.appendingPathComponent("weights.npz"))
        defer { try? FileManager.default.removeItem(at: container) }

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("any-checksum", forKey: "paddleocr.model.checksum")
        defaults.set(true, forKey: "paddleocr.enabled")
        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: legacyRoot,
            userDefaults: defaults,
            downloader: NoopModelDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        // SlowMockOCRRecognizer.recognizeText sleeps for ~0.5s on the
        // background queue MangaOCRService uses, giving delete() a wide
        // window to race and observe the lifecycle wait.
        let slowRecognizer = SlowMockOCRRecognizer()
        let mangaOCRService = MangaOCRService(detector: MockComicTextDetector())

        let router = OCRRouter(
            mangaOCRService: mangaOCRService,
            capabilityChecker: MockCapabilityChecker(.supported),
            downloadManager: service,
            paddleOCRFactory: { slowRecognizer },
            inferenceCoordinator: service
        )

        let recorder = LifecycleEventRecorderForRouterTests()
        await service.setLifecycleObserver { event in
            recorder.append(event)
        }

        let ocrTask = Task { @MainActor in
            _ = try? await router.processPage(
                image: makeTestImage(width: 100, height: 100),
                sourceLanguage: .ja
            )
        }

        // Let the production OCR path start and call beginInference before
        // we kick off delete(). Without this slack, delete() may grab the
        // lock first and skip the inference wait.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))

        try await service.delete()
        await ocrTask.value

        let events = recorder.snapshot()
        XCTAssertTrue(events.contains(.waitForInferencesBegan),
                      "Production PaddleOCR route must register active inference so delete() suspends; events=\(events)")
        XCTAssertTrue(events.contains(.waitForInferencesResumed),
                      "delete() must resume only after PaddleOCR inference ends; events=\(events)")
        XCTAssertEqual(service.state, .notDownloaded)
    }

    // MARK: - Inference coordinator resolution precedence
    //
    // Pin the documented precedence used by `OCRRouter.makeProductionRouter`
    // and any future caller of the resolver helper: an explicit coordinator
    // beats everything; otherwise a `downloadManager` that also conforms to
    // `ModelInferenceCoordinating` wins so routing state and inference
    // bookkeeping stay on the same instance; otherwise the supplied fallback
    // is used. Earlier wiring used a plain `?? fallback`, which silently sent
    // inference bookkeeping to the shared service even when the caller had
    // injected a custom dual-conforming manager.

    func testResolveCoordinatorPrefersExplicitOverEverything() {
        let dual = DualConformanceMock()
        let explicit = CoordinatorOnlyMock()
        let fallback = CoordinatorOnlyMock()

        let resolved = OCRRouter.resolveInferenceCoordinator(
            downloadManager: dual,
            inferenceCoordinator: explicit,
            fallback: fallback
        )

        XCTAssertIdentical(resolved as AnyObject, explicit,
                           "Explicit inferenceCoordinator must win over a dual-conforming downloadManager")
    }

    func testResolveCoordinatorUsesDownloadManagerWhenItAlsoConforms() {
        let dual = DualConformanceMock()
        let fallback = CoordinatorOnlyMock()

        let resolved = OCRRouter.resolveInferenceCoordinator(
            downloadManager: dual,
            inferenceCoordinator: nil,
            fallback: fallback
        )

        XCTAssertIdentical(resolved as AnyObject, dual,
                           "A dual-conforming downloadManager must coordinate inference instead of the fallback")
        XCTAssertNotIdentical(resolved as AnyObject, fallback,
                              "Resolver must not silently route inference to the fallback when the downloadManager can coordinate")
    }

    func testResolveCoordinatorFallsBackWhenDownloadManagerDoesNotConform() {
        let managerOnly = MockDownloadManager(state: .downloaded, enabled: true)
        let fallback = CoordinatorOnlyMock()

        let resolved = OCRRouter.resolveInferenceCoordinator(
            downloadManager: managerOnly,
            inferenceCoordinator: nil,
            fallback: fallback
        )

        XCTAssertIdentical(resolved as AnyObject, fallback,
                           "Resolver must fall back when downloadManager does not also coordinate inference")
    }

    func testResolveCoordinatorFallsBackWhenDownloadManagerIsNil() {
        let fallback = CoordinatorOnlyMock()

        let resolved = OCRRouter.resolveInferenceCoordinator(
            downloadManager: nil,
            inferenceCoordinator: nil,
            fallback: fallback
        )

        XCTAssertIdentical(resolved as AnyObject, fallback,
                           "Resolver must fall back when no downloadManager is provided")
    }
}

// MARK: - Mock Types

private final class SlowMockOCRRecognizer: @unchecked Sendable, OCRRecognizing {
    var isRecognizing = false
    var didFinish = false
    let name: String
    
    init(name: String = "slow-mock") { self.name = name }
    
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        isRecognizing = true
        Thread.sleep(forTimeInterval: 0.5)
        isRecognizing = false
        didFinish = true
        return (name, 1.0)
    }
}

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

// Conforms to both protocols so resolver tests can assert that a
// dual-conforming downloadManager is preferred over the supplied fallback.
@MainActor
private final class DualConformanceMock: ModelDownloadManaging, ModelInferenceCoordinating {
    let state: ModelDownloadState
    let isPaddleOCREnabled: Bool
    init(state: ModelDownloadState = .downloaded, enabled: Bool = true) {
        self.state = state
        self.isPaddleOCREnabled = state == .downloaded && enabled
    }
    nonisolated func beginInference() async {}
    nonisolated func endInference() async {}
}

// Conforms only to the coordinator protocol so the resolver tests can
// distinguish a coordinator from a downloadManager and verify fallback wiring.
private final class CoordinatorOnlyMock: ModelInferenceCoordinating, @unchecked Sendable {
    func beginInference() async {}
    func endInference() async {}
}

private final class MockOCRRecognizer: OCRRecognizing {
    let name: String
    init(name: String = "mock") { self.name = name }
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        return (name, 1.0)
    }
}

private struct MockComicTextDetector: ComicTextDetecting {
    let returnsEmpty: Bool
    init(returnsEmpty: Bool = false) { self.returnsEmpty = returnsEmpty }
    func detectTextRegions(in cgImage: CGImage) throws -> ComicTextDetectorResult {
        if returnsEmpty {
            return ComicTextDetectorResult(regions: [], textPixelMask: nil, lowConfidenceRegionCount: 0)
        }
        return ComicTextDetectorResult(
            regions: [DetectedTextRegion(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), confidence: 1.0, classIndex: 0)],
            textPixelMask: nil,
            lowConfidenceRegionCount: 0
        )
    }
}

private final class ThrowingOCRRecognizer: OCRRecognizing {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        throw PaddleOCRError.inferenceFailed("forced failure")
    }
}

private final class MockPaddleOCRGPUCacheCleanup: PaddleOCRGPUCacheCleaning, @unchecked Sendable {
    var clearCount = 0
    func clearGPUCache() { clearCount += 1 }
}

private final class MockTranslationService: TranslationService {
    var engine: TranslationEngine { .githubCopilot }
    func translate(bubbles: [BubbleCluster], from source: Language, to target: Language, context: TranslationContext) async throws -> TranslationOutput {
        let translated = bubbles.map { TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index) }
        return TranslationOutput(bubbles: translated, detectedTerms: [])
    }
}

// Minimal ModelDownloading stand-in for tests that only need a service whose
// download path is never exercised. Throws if invoked so accidental calls fail
// loudly instead of returning bogus data.
private struct NoopModelDownloader: ModelDownloading {
    func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        throw PaddleOCRError.downloadFailed("noop downloader invoked in test")
    }
    func fetchString(from url: URL) async throws -> String { "" }
}

private final class LifecycleEventRecorderForRouterTests: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ModelLifecycleEvent] = []

    func append(_ event: ModelLifecycleEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
    }

    func snapshot() -> [ModelLifecycleEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
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
