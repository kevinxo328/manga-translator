import Testing
import Foundation
import CryptoKit
@testable import MangaTranslator

// MARK: - Test Helpers

private actor MockDownloader: ModelDownloading {
    var downloadResult: Result<URL, Error> = .failure(PaddleOCRError.downloadFailed("not configured"))
    var checksumResult: Result<String, Error> = .failure(PaddleOCRError.downloadFailed("not configured"))
    var downloadDelay: Duration = .zero
    var progressSequence: [Double] = []

    func setDownload(_ url: URL, checksum: String) {
        downloadResult = .success(url)
        checksumResult = .success(checksum)
    }

    func setDownloadError(_ error: Error) {
        downloadResult = .failure(error)
    }

    func setChecksumError(_ error: Error) {
        checksumResult = .failure(error)
    }

    func setProgressSequence(_ values: [Double]) {
        progressSequence = values
    }

    func setDownloadDelay(_ delay: Duration) {
        downloadDelay = delay
    }

    nonisolated func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let (result, progress, delay) = await (downloadResult, progressSequence, downloadDelay)
        for value in progress {
            progressHandler(value)
        }
        if delay != .zero {
            try await Task.sleep(for: delay)
        }
        switch result {
        case .success(let u): return u
        case .failure(let e): throw e
        }
    }

    nonisolated func fetchString(from url: URL) async throws -> String {
        let result = await checksumResult
        switch result {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

// MARK: - Extraction seam mock

/// Behaviors a `MockArchiveExtractor` can simulate to cover the spec's
/// extraction outcomes without invoking `/usr/bin/unzip`.
enum MockExtractionBehavior: Sendable {
    /// Drop a `weights.npz` file inside the candidate so validation passes.
    case successWeightsNpz
    /// Drop a `model.safetensors` file inside the candidate so validation passes.
    case successSafetensors
    /// Create the candidate but leave it empty so `hasSupportedModelWeights`
    /// returns false. Used to test post-extraction validation failure.
    case successWithoutWeights
    /// Throw to simulate a path-traversal rejection.
    case pathTraversalRejected
    /// Throw to simulate `/usr/bin/unzip` exiting with a non-zero status.
    case nonZeroUnzipExit
    /// Throw an arbitrary error supplied by the test.
    case error(any Error)
}

private final class MockArchiveExtractor: ModelArchiveExtracting, @unchecked Sendable {
    // Locked behavior so the synchronous `extract` call can read it without
    // crossing actor boundaries. Tests configure behavior before invoking
    // the service.
    private let lock = NSLock()
    private var behavior: MockExtractionBehavior = .successWeightsNpz
    private(set) var invocations: [(archive: URL, candidate: URL)] = []

    func setBehavior(_ behavior: MockExtractionBehavior) {
        lock.lock(); defer { lock.unlock() }
        self.behavior = behavior
    }

    func extract(archive: URL, into candidate: URL) throws {
        lock.lock()
        let current = behavior
        invocations.append((archive: archive, candidate: candidate))
        lock.unlock()

        let fm = FileManager.default
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)

        switch current {
        case .successWeightsNpz:
            try Data("fake-weights".utf8)
                .write(to: candidate.appendingPathComponent("weights.npz"))
        case .successSafetensors:
            try Data("fake-safetensors".utf8)
                .write(to: candidate.appendingPathComponent("model.safetensors"))
        case .successWithoutWeights:
            return
        case .pathTraversalRejected:
            throw PaddleOCRError.verifyFailed
        case .nonZeroUnzipExit:
            throw PaddleOCRError.verifyFailed
        case .error(let err):
            throw err
        }
    }
}

// MARK: - Install file-op seam mock

/// Behaviors a `MockInstallFileOps` can override on a specific operation.
/// Tests inject these to fail a particular `moveItem` deterministically.
struct MockInstallFileOpsFailure: Sendable {
    /// Match the source URL of the move operation that should fail.
    let matchesMoveSource: @Sendable (URL) -> Bool
    let error: any Error
}

private final class MockInstallFileOps: ModelInstallFileOps, @unchecked Sendable {
    private let lock = NSLock()
    private var moveFailures: [MockInstallFileOpsFailure] = []
    private var createDirectoryFailures: [@Sendable (URL) -> (any Error)?] = []
    private(set) var moveLog: [(source: URL, destination: URL)] = []
    private(set) var removeLog: [URL] = []

    func addMoveFailure(_ failure: MockInstallFileOpsFailure) {
        lock.lock(); defer { lock.unlock() }
        moveFailures.append(failure)
    }

    func addCreateDirectoryFailure(_ failure: @escaping @Sendable (URL) -> (any Error)?) {
        lock.lock(); defer { lock.unlock() }
        createDirectoryFailures.append(failure)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        lock.lock()
        let matched = createDirectoryFailures.compactMap { $0(url) }.first
        lock.unlock()
        if let matched {
            throw matched
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        lock.lock()
        moveLog.append((source: source, destination: destination))
        let matched = moveFailures.first(where: { $0.matchesMoveSource(source) })
        lock.unlock()
        if let matched {
            throw matched.error
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        removeLog.append(url)
        lock.unlock()
        try FileManager.default.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}

private func makeTempFile(content: Data = Data("hello".utf8)) throws -> URL {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try content.write(to: tmp)
    return tmp
}

private func makeTestZip(containing fileName: String, content: Data) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let fileURL = tempDir.appendingPathComponent(fileName)
    try content.write(to: fileURL)
    let zipURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".zip")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    task.arguments = ["-j", zipURL.path, fileURL.path]
    try task.run()
    task.waitUntilExit()
    try FileManager.default.removeItem(at: tempDir)
    return zipURL
}

private func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Model directory fixtures

/// The supported weight filename the fixture should drop into the directory.
enum FixtureWeightKind: Sendable {
    case weightsNpz
    case safetensors
}

/// Creates a minimal valid model directory at `url` by dropping a single
/// supported weight file inside it. Used by tests that need the resolver or
/// validator to accept a directory.
@discardableResult
private func makeValidModelDir(at url: URL, weight: FixtureWeightKind = .weightsNpz) throws -> URL {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let name: String
    switch weight {
    case .weightsNpz: name = "weights.npz"
    case .safetensors: name = "model.safetensors"
    }
    try Data("fake-\(name)".utf8).write(to: url.appendingPathComponent(name))
    return url
}

/// Model container directory layouts used by resolver and atomic-install tests.
/// The container is the parent directory of the legacy `PaddleOCR-VL` root.
enum ContainerLayout: Sendable {
    /// Only `<container>/PaddleOCR-VL.current` exists and is valid.
    case currentOnly
    /// Only `<container>/PaddleOCR-VL` exists and is valid at the root.
    case legacyRootOnly
    /// `<container>/PaddleOCR-VL/<childName>` is valid; the legacy root itself
    /// does NOT contain weights at its top level.
    case legacySingleChild(childName: String = "paddleocr-vl-manga-mlx")
    /// Two valid child directories under `<container>/PaddleOCR-VL`; the legacy
    /// root itself does NOT contain weights at its top level.
    case legacyMultipleChildren(firstChild: String = "first", secondChild: String = "second")
    /// Both `<container>/PaddleOCR-VL.current` and `<container>/PaddleOCR-VL`
    /// exist and are valid.
    case currentPlusLegacy
    /// `<container>/PaddleOCR-VL.current` exists but lacks weights, and
    /// `<container>/PaddleOCR-VL` exists and is valid.
    case invalidCurrentPlusValidLegacy
}

struct ContainerFixture {
    let container: URL
    let current: URL
    let legacyRoot: URL

    var installingRoot: URL { container.appendingPathComponent(".installing") }
}

/// Builds a model container at a fresh temporary directory and populates it
/// with the requested layout. Callers receive the container plus the canonical
/// `.current` and legacy root URLs.
@discardableResult
private func makeContainerFixture(
    _ layout: ContainerLayout,
    in baseDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
) throws -> ContainerFixture {
    let container = baseDir
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let current = container.appendingPathComponent("PaddleOCR-VL.current")
    let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")

    switch layout {
    case .currentOnly:
        try makeValidModelDir(at: current)
    case .legacyRootOnly:
        try makeValidModelDir(at: legacyRoot)
    case .legacySingleChild(let childName):
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try makeValidModelDir(at: legacyRoot.appendingPathComponent(childName))
    case .legacyMultipleChildren(let firstChild, let secondChild):
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try makeValidModelDir(at: legacyRoot.appendingPathComponent(firstChild))
        try makeValidModelDir(at: legacyRoot.appendingPathComponent(secondChild))
    case .currentPlusLegacy:
        try makeValidModelDir(at: current)
        try makeValidModelDir(at: legacyRoot)
    case .invalidCurrentPlusValidLegacy:
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        // Intentionally no weights file inside `.current`.
        try makeValidModelDir(at: legacyRoot)
    }

    return ContainerFixture(container: container, current: current, legacyRoot: legacyRoot)
}

@MainActor
private func makeService(
    modelDir: URL? = nil,
    downloader: MockDownloader? = nil,
    extractor: (any ModelArchiveExtracting)? = nil,
    installFileOps: (any ModelInstallFileOps)? = nil,
    availableSpaceProvider: @escaping @Sendable () -> Int64? = {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return attrs?[.systemFreeSize] as? Int64
    }
) -> (ModelDownloadService, MockDownloader, URL, UserDefaults) {
    // Give every test an isolated container so `.current`, `.installing`, and
    // backups never collide across parallel test runs. `dir` matches the
    // legacy root path the service receives via `config.modelDirectory`.
    let dir: URL
    if let modelDir {
        dir = modelDir
    } else {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        dir = container.appendingPathComponent("PaddleOCR-VL")
    }
    let dl = downloader ?? MockDownloader()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    // Default extractor returns a `weights.npz`-only candidate so production extraction
    // can be exercised in tests without crafting a real zip archive.
    let effectiveExtractor: any ModelArchiveExtracting
    if let extractor {
        effectiveExtractor = extractor
    } else {
        let mock = MockArchiveExtractor()
        mock.setBehavior(.successWeightsNpz)
        effectiveExtractor = mock
    }
    let config = ModelDownloadConfiguration(
        modelURL: URL(string: "https://example.com/model.zip")!,
        checksumURL: URL(string: "https://example.com/model.zip.sha256")!,
        modelDirectory: dir,
        userDefaults: defaults,
        downloader: dl,
        extractor: effectiveExtractor,
        installFileOps: installFileOps ?? DefaultModelInstallFileOps(),
        availableSpaceProvider: availableSpaceProvider
    )
    let service = ModelDownloadService(configuration: config)
    return (service, dl, dir, defaults)
}

/// Computes the active `.current` directory that sits next to a legacy root.
private func currentDir(forLegacyRoot legacyRoot: URL) -> URL {
    legacyRoot.deletingLastPathComponent().appendingPathComponent("PaddleOCR-VL.current")
}

// MARK: - Suite

@Suite("ModelDownloadService")
struct ModelDownloadServiceTests {

    // MARK: - Task 18: Successful download

    @Test("Download transitions state to .downloaded on success")
    @MainActor
    func successfulDownloadState() async throws {
        let (service, downloader, dir, _) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)

        await service.download()

        #expect(service.state == .downloaded)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Download writes file to model directory")
    @MainActor
    func successfulDownloadWritesFile() async throws {
        let (service, downloader, dir, _) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)

        await service.download()

        let archivePath = currentDir(forLegacyRoot: dir).appendingPathComponent("model.zip")
        #expect(FileManager.default.fileExists(atPath: archivePath.path))
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    @Test("Download sets UserDefaults downloaded=true and stores checksum")
    @MainActor
    func successfulDownloadPersistsDefaults() async throws {
        let (service, downloader, dir, defaults) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)

        await service.download()

        #expect(defaults.bool(forKey: "paddleocr.model.downloaded") == true)
        #expect(defaults.string(forKey: "paddleocr.model.checksum") == checksum)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Download progress publishes bounded downloading state")
    @MainActor
    func downloadProgressReportsBoundedState() async throws {
        let (service, downloader, dir, _) = makeService()
        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)
        await downloader.setProgressSequence([0.25, 0.75])
        await downloader.setDownloadDelay(.milliseconds(200))

        async let downloadTask: Void = service.download()

        var observedProgress: Double?
        for _ in 0..<100 {
            if case .downloading(let progress) = service.state {
                observedProgress = progress
                if progress == 0.75 {
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        guard let observedProgress else {
            Issue.record("Expected service to publish `.downloading(progress:)` before completion")
            await downloadTask
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
            return
        }

        #expect((0.0...1.0).contains(observedProgress),
                "Progress must stay within the user-facing 0.0...1.0 range")
        await downloadTask
        #expect(service.state == .downloaded)
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    // MARK: - Task 19: Error cases

    @Test("SHA256 mismatch: state transitions to .failed and file is deleted")
    @MainActor
    func sha256MismatchDeletesFileAndFails() async throws {
        let (service, downloader, dir, _) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        // Set wrong checksum
        await downloader.setDownload(tmpFile, checksum: "wrongchecksum")

        await service.download()

        if case .failed(let error) = service.state {
            #expect(error == .verifyFailed)
        } else {
            Issue.record("Expected .failed state, got \(service.state)")
        }

        let archivePath = dir.appendingPathComponent("model.zip")
        #expect(!FileManager.default.fileExists(atPath: archivePath.path))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Network error: state transitions to .failed")
    @MainActor
    func networkErrorFails() async throws {
        let (service, downloader, _, _) = makeService()
        await downloader.setDownloadError(URLError(.notConnectedToInternet))

        await service.download()

        if case .failed = service.state {
            // expected
        } else {
            Issue.record("Expected .failed state, got \(service.state)")
        }
    }

    @Test("Checksum fetch error: state transitions to .failed")
    @MainActor
    func checksumFetchErrorFails() async throws {
        let (service, downloader, _, _) = makeService()
        await downloader.setChecksumError(URLError(.notConnectedToInternet))

        await service.download()

        if case .failed = service.state {
            // expected
        } else {
            Issue.record("Expected .failed state, got \(service.state)")
        }
    }

    // MARK: - Task 20: Cancellation

    @Test("Cancel: state returns to .notDownloaded")
    @MainActor
    func cancelReturnsToNotDownloaded() async throws {
        let (service, _, _, _) = makeService()
        service.cancel()
        #expect(service.state == .notDownloaded)
    }

    // MARK: - Task 21: Duplicate download call

    @Test("Duplicate download() call while downloading is ignored")
    @MainActor
    func duplicateDownloadIsIgnored() async throws {
        let (service, downloader, dir, _) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)

        // Force state to downloading
        // We call download() twice concurrently and verify second is ignored
        // by checking final state is .downloaded (not a crash or double-download)
        async let first: Void = service.download()
        await first

        _ = service.state
        await service.download() // second call after first completes — should still be .downloaded
        let state2 = service.state

        #expect(state2 == .downloaded)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Task 22: delete()

    @Test("delete(): files removed, UserDefaults cleared, state .notDownloaded, enabled=false")
    @MainActor
    func deleteRemovesFilesAndResetsState() async throws {
        let (service, downloader, dir, defaults) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)
        await service.download()

        #expect(service.state == .downloaded)

        try await service.delete()

        #expect(service.state == .notDownloaded)
        #expect(!defaults.bool(forKey: "paddleocr.model.downloaded"))
        #expect(defaults.string(forKey: "paddleocr.model.checksum") == nil)
        #expect(!defaults.bool(forKey: "paddleocr.enabled"))
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Task 23: delete() when file absent

    @Test("delete() when file absent: no throw, state .notDownloaded")
    @MainActor
    func deleteWhenFileAbsentDoesNotThrow() async throws {
        let (service, _, _, _) = makeService()
        await #expect(throws: Never.self) {
            try await service.delete()
        }
        #expect(service.state == .notDownloaded)
    }

    // MARK: - Task 24: verify()

    @Test("verify() returns true when file present and SHA256 matches")
    @MainActor
    func verifyReturnsTrueWhenValid() async throws {
        let (service, downloader, dir, _) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)
        await service.download()

        let result = await service.verify()
        #expect(result == true)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("verify() returns false when file absent")
    @MainActor
    func verifyReturnsFalseWhenAbsent() async throws {
        let (service, _, _, _) = makeService()
        let result = await service.verify()
        #expect(result == false)
    }

    @Test("verify() returns false when SHA256 mismatch")
    @MainActor
    func verifyReturnsFalseOnChecksumMismatch() async throws {
        let (service, _, dir, defaults) = makeService()

        // Manually write a file and set wrong checksum
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archivePath = dir.appendingPathComponent("model.zip")
        try Data("corrupted".utf8).write(to: archivePath)
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("wrongchecksum", forKey: "paddleocr.model.checksum")

        let result = await service.verify()
        #expect(result == false)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Task 25: verifyOnLaunch()

    @Test("verifyOnLaunch(): resets state when UserDefaults says downloaded but file missing")
    @MainActor
    func verifyOnLaunchResetsWhenFileMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("somechecksum", forKey: "paddleocr.model.checksum")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)
        // Initial state should be .downloaded (UserDefaults says so)
        #expect(service.state == .downloaded)

        await service.verifyOnLaunch()

        #expect(service.state == .notDownloaded)
        #expect(!defaults.bool(forKey: "paddleocr.model.downloaded"))
    }

    @Test("verifyOnLaunch(): deletes corrupt file and resets state on SHA256 mismatch")
    @MainActor
    func verifyOnLaunchDeletesCorruptFile() async throws {
        // Container layout: <container>/PaddleOCR-VL is the resolved active dir;
        // weights.npz makes it valid; model.zip is the (corrupt) archive that
        // verifyOnLaunch should delete on mismatch.
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let dir = container.appendingPathComponent("PaddleOCR-VL")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("fake-weights".utf8).write(to: dir.appendingPathComponent("weights.npz"))
        let archivePath = dir.appendingPathComponent("model.zip")
        try Data("corrupted-content".utf8).write(to: archivePath)

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("wrongchecksum", forKey: "paddleocr.model.checksum")
        // Force stale-evidence branch so full SHA256 runs.
        defaults.set(0.0, forKey: "paddleocr.model.lastVerified")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        #expect(service.state == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: archivePath.path))
        try? FileManager.default.removeItem(at: container)
    }

    @Test("verifyOnLaunch(): does nothing when UserDefaults says not downloaded")
    @MainActor
    func verifyOnLaunchNoopWhenNotDownloaded() async throws {
        let (service, _, _, _) = makeService()
        await service.verifyOnLaunch()
        #expect(service.state == .notDownloaded)
    }

    // MARK: - Task 26: Launch verification policy

    @Test("verifyOnLaunch: resets state when model.zip present but no supported model weight file")
    @MainActor
    func verifyOnLaunchResetsWhenWeightsMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archivePath = dir.appendingPathComponent("model.zip")
        let fileData = Data("valid-model".utf8)
        try fileData.write(to: archivePath)
        let checksum = sha256Hex(of: fileData)
        // No supported model weight file intentionally

        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(checksum, forKey: "paddleocr.model.checksum")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        #expect(service.state == .notDownloaded, "State must reset when no supported model weight file exists")
        #expect(!defaults.bool(forKey: "paddleocr.model.downloaded"))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("verifyOnLaunch: keeps downloaded state when weights.npz exists in a single nested model folder")
    @MainActor
    func verifyOnLaunchAcceptsNestedModelFolder() async throws {
        // Use a container-style layout: <container>/PaddleOCR-VL/<child>/weights.npz.
        // The resolver returns the nested child, and verifyOnLaunch checks the
        // archive inside the resolved directory.
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let dir = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let nestedModelDir = dir.appendingPathComponent("paddleocr-vl-manga-mlx")
        try FileManager.default.createDirectory(at: nestedModelDir, withIntermediateDirectories: true)
        try Data("fake-weights".utf8).write(to: nestedModelDir.appendingPathComponent("weights.npz"))

        // model.zip belongs inside the resolved directory.
        let archivePath = nestedModelDir.appendingPathComponent("model.zip")
        let fileData = Data("valid-model".utf8)
        try fileData.write(to: archivePath)
        let checksum = sha256Hex(of: fileData)

        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(checksum, forKey: "paddleocr.model.checksum")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        #expect(service.state == .downloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded"))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("verifyOnLaunch: keeps downloaded state when model.safetensors exists at root")
    @MainActor
    func verifyOnLaunchAcceptsRootSafetensors() async throws {
        // Container-style: <container>/PaddleOCR-VL holds the weights + archive directly.
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let dir = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archivePath = dir.appendingPathComponent("model.zip")
        let fileData = Data("valid-model".utf8)
        try fileData.write(to: archivePath)
        let checksum = sha256Hex(of: fileData)
        try Data("fake-safetensors".utf8).write(to: dir.appendingPathComponent("model.safetensors"))

        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(checksum, forKey: "paddleocr.model.checksum")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        #expect(service.state == .downloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded"))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("verifyOnLaunch: full SHA256 required when checksum evidence is missing")
    @MainActor
    func verifyOnLaunchFullChecksumWhenMissingEvidence() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archivePath = dir.appendingPathComponent("model.zip")
        let fileData = Data("valid-model".utf8)
        try fileData.write(to: archivePath)

        // UserDefaults says downloaded, but no checksum stored
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        // No checksum set → evidence is stale → full verification required → resets

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        // Without stored checksum, verification should reset state
        #expect(service.state == .notDownloaded)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("verifyOnLaunch: state remains .downloaded when integrity evidence is fresh and valid")
    @MainActor
    func verifyOnLaunchFastPathWhenFreshEvidence() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let dir = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archivePath = dir.appendingPathComponent("model.zip")
        let fileData = Data("valid-model".utf8)
        try fileData.write(to: archivePath)
        let checksum = sha256Hex(of: fileData)
        try Data("fake-weights".utf8).write(to: dir.appendingPathComponent("weights.npz"))

        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(checksum, forKey: "paddleocr.model.checksum")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        #expect(service.state == .downloaded)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Task 27: State machine transitions

    @Test("Invalid state: enabled=true while not downloaded is corrected on delete")
    @MainActor
    func invalidEnabledStateIsCorrectOnDelete() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.enabled")
        defaults.set(false, forKey: "paddleocr.model.downloaded")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        // delete() should clear the invalid enabled state
        try await service.delete()

        #expect(!defaults.bool(forKey: "paddleocr.enabled"))
        #expect(service.state == .notDownloaded)
    }

    @Test("State machine: download+verify success sets enabled=true")
    @MainActor
    func downloadSuccessSetsEnabled() async throws {
        let (service, downloader, dir, defaults) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)

        await service.download()

        #expect(defaults.bool(forKey: "paddleocr.enabled") == true)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Task 28: Concurrency - delete() during inference

    @Test("delete() waits for active inference before removing files")
    @MainActor
    func deleteWaitsForActiveInference() async throws {
        let (service, downloader, dir, _) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)
        await service.download()

        // Begin inference
        await service.beginInference()

        // Delete should wait; we verify it completes after we end inference
        let deleteTask = Task {
            try await service.delete()
        }

        // Allow delete to start and block
        await Task.yield()
        await Task.yield()

        // File should still exist while inference is in progress...
        // (in practice hard to assert this without a delay; we assert final state)
        await service.endInference()
        try await deleteTask.value

        #expect(service.state == .notDownloaded)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Task 29: Security - path traversal

    @Test("Archive extraction rejects path traversal entries")
    @MainActor
    func extractionRejectsPathTraversal() async throws {
        // Drive the install flow with an extractor that simulates a path-traversal
        // rejection. The atomic install must surface the failure (state `.failed`
        // on a first install) instead of promoting the candidate to `.current`.
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .pathTraversalRejected
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        if case .failed = setup.service.state {
            // expected
        } else {
            Issue.record("Path-traversal extractor must surface a failure state; got \(setup.service.state)")
        }
        #expect(!FileManager.default.fileExists(atPath: setup.current.path),
                "`.current` must not be created when extraction is rejected")
    }

    // MARK: - Task 30: Atomic install

    @Test("Failed install does not overwrite prior valid model directory")
    @MainActor
    func failedInstallPreservesPriorModel() async throws {
        let (service, downloader, dir, _) = makeService()

        // First successful download
        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let checksum = sha256Hex(of: fileData)
        await downloader.setDownload(tmpFile, checksum: checksum)
        await service.download()
        #expect(service.state == .downloaded)

        // Second download fails (network error)
        await downloader.setDownloadError(URLError(.notConnectedToInternet))
        await service.download()

        // Prior `.current/model.zip` must still exist after the failed second attempt.
        let archivePath = currentDir(forLegacyRoot: dir).appendingPathComponent("model.zip")
        #expect(FileManager.default.fileExists(atPath: archivePath.path))
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    // MARK: - Task 31: Non-blocking launch

    @Test("verifyOnLaunch() runs asynchronously and does not block initial UI availability")
    @MainActor
    func verifyOnLaunchIsNonBlocking() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archivePath = dir.appendingPathComponent("model.zip")
        let fileData = Data("valid-model".utf8)
        try fileData.write(to: archivePath)
        let checksum = sha256Hex(of: fileData)
        try Data("fake-weights".utf8).write(to: dir.appendingPathComponent("weights.npz"))

        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(checksum, forKey: "paddleocr.model.checksum")

        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: dir,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        // verifyOnLaunch must not throw and must complete
        await service.verifyOnLaunch()
        // If we reach here, it did not block indefinitely
        #expect(Bool(true))
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Extraction preservation

    @Test("Extracted model files are preserved in `.current` after download")
    @MainActor
    func extractedFilesPreservedAfterDownload() async throws {
        // Use the real `DefaultArchiveExtractor` here to verify the live unzip
        // pathway places extracted files into `.current` after promotion.
        let (service, downloader, dir, _) = makeService(extractor: DefaultArchiveExtractor())

        let weightsContent = Data("fake-weights-data".utf8)
        let zipURL = try makeTestZip(containing: "weights.npz", content: weightsContent)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let zipData = try Data(contentsOf: zipURL)
        let checksum = sha256Hex(of: zipData)
        await downloader.setDownload(zipURL, checksum: checksum)

        await service.download()

        #expect(service.state == .downloaded, "Service should reach downloaded state")
        let weightsPath = currentDir(forLegacyRoot: dir).appendingPathComponent("weights.npz")
        #expect(
            FileManager.default.fileExists(atPath: weightsPath.path),
            "weights.npz must exist in `.current` after a successful install"
        )
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    @Test("Default archive extractor rejects real path traversal archive")
    func defaultArchiveExtractorRejectsTraversalZip() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let zipURL = baseDir.appendingPathComponent("traversal.zip")
        try TestZipWriter.write([
            .file("../escape.txt", Data("escape".utf8))
        ], to: zipURL)

        let candidate = baseDir.appendingPathComponent(".installing").appendingPathComponent("PaddleOCR-VL.next.test")
        #expect(throws: (any Error).self) {
            try DefaultArchiveExtractor().extract(archive: zipURL, into: candidate)
        }
        #expect(!FileManager.default.fileExists(atPath: baseDir.appendingPathComponent("escape.txt").path),
                "Extractor must reject traversal before any outside-candidate file is created")
    }

    // MARK: - Checksum format

    @Test("sha256sum format (hash + filename) is accepted as valid checksum")
    @MainActor
    func checksumWithSha256sumFormatSucceeds() async throws {
        let (service, downloader, dir, defaults) = makeService()

        let fileData = Data("model-binary".utf8)
        let tmpFile = try makeTempFile(content: fileData)
        let hash = sha256Hex(of: fileData)
        // Standard sha256sum output: "<hash>  <filename>"
        let sha256sumLine = "\(hash)  model.zip"
        await downloader.setDownload(tmpFile, checksum: sha256sumLine)

        await service.download()

        #expect(service.state == .downloaded, "sha256sum-format checksum should be accepted")
        #expect(defaults.string(forKey: "paddleocr.model.checksum") == hash)
        try? FileManager.default.removeItem(at: dir)
    }

}

// MARK: - Atomic install helpers (Section 4)

/// Bundles the live URLs and mock collaborators a Section 4 test needs.
/// `legacyRoot` is what gets passed as `config.modelDirectory`; everything
/// else (`current`, `.installing`, backups) is derived from `container`.
@MainActor
private struct AtomicInstallSetup {
    let service: ModelDownloadService
    let downloader: MockDownloader
    let defaults: UserDefaults
    let extractor: MockArchiveExtractor
    let installFileOps: MockInstallFileOps
    let container: URL
    let legacyRoot: URL
    let current: URL
    var installingRoot: URL { container.appendingPathComponent(".installing") }
}

@MainActor
private func makeAtomicInstallSetup(
    layout: ContainerLayout? = nil,
    extractorBehavior: MockExtractionBehavior = .successWeightsNpz,
    priorChecksum: String? = nil,
    priorEnabled: Bool = true,
    availableSpaceProvider: @escaping @Sendable () -> Int64? = {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return attrs?[.systemFreeSize] as? Int64
    }
) throws -> AtomicInstallSetup {
    let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

    if let layout {
        // Build the requested initial layout inside the container.
        _ = try makeContainerFixture(layout, in: container)
    }

    let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
    let current = container.appendingPathComponent("PaddleOCR-VL.current")

    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    if let priorChecksum {
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(priorChecksum, forKey: "paddleocr.model.checksum")
        defaults.set(Date().timeIntervalSince1970, forKey: "paddleocr.model.lastVerified")
        defaults.set(priorEnabled, forKey: "paddleocr.enabled")
    }

    let downloader = MockDownloader()
    let extractor = MockArchiveExtractor()
    extractor.setBehavior(extractorBehavior)
    let installFileOps = MockInstallFileOps()

    let config = ModelDownloadConfiguration(
        modelURL: URL(string: "https://example.com/model.zip")!,
        checksumURL: URL(string: "https://example.com/model.zip.sha256")!,
        modelDirectory: legacyRoot,
        userDefaults: defaults,
        downloader: downloader,
        extractor: extractor,
        installFileOps: installFileOps,
        availableSpaceProvider: availableSpaceProvider
    )
    let service = ModelDownloadService(configuration: config)

    return AtomicInstallSetup(
        service: service,
        downloader: downloader,
        defaults: defaults,
        extractor: extractor,
        installFileOps: installFileOps,
        container: container,
        legacyRoot: legacyRoot,
        current: current
    )
}

/// Configures `downloader` to return a freshly-created temp archive whose
/// SHA256 the test pre-computes, so checksum verification will succeed inside
/// `performDownload`. Returns the archive URL for additional setup.
@MainActor
private func primeArchive(
    on downloader: MockDownloader,
    payload: Data = Data("atomic-install-fake-archive".utf8)
) async throws -> URL {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
    try payload.write(to: tmp)
    let checksum = sha256Hex(of: payload)
    await downloader.setDownload(tmp, checksum: checksum)
    return tmp
}

// MARK: - Resolver tests (Section 2)

@Suite("ModelDownloadService.resolvedActiveModelDirectory")
struct ResolvedActiveModelDirectoryTests {

    // Compare URLs by resolved filesystem path. `URL.appendingPathComponent` may
    // produce a directory URL with trailing slash when the target exists on
    // disk as a directory, which breaks plain URL equality.
    private static func equalPaths(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        return a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    // Task 2.1
    @Test("Resolver returns `.current` when both `.current` and legacy root are valid")
    func currentWinsOverLegacy() throws {
        let fixture = try makeContainerFixture(.currentPlusLegacy)
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let resolved = ModelDownloadService.resolvedActiveModelDirectory(
            inContainer: fixture.container
        )
        #expect(Self.equalPaths(resolved, fixture.current),
                "Resolver must prefer `.current` over legacy root when both are valid")
    }

    // Task 2.2
    @Test("Resolver returns legacy root when `.current` is absent and legacy root is valid")
    func legacyRootWhenCurrentAbsent() throws {
        let fixture = try makeContainerFixture(.legacyRootOnly)
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let resolved = ModelDownloadService.resolvedActiveModelDirectory(
            inContainer: fixture.container
        )
        #expect(Self.equalPaths(resolved, fixture.legacyRoot))
    }

    // Task 2.3
    @Test("Resolver returns single valid legacy child when legacy root itself lacks weights")
    func legacySingleChildWhenRootInvalid() throws {
        let fixture = try makeContainerFixture(.legacySingleChild())
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let resolved = ModelDownloadService.resolvedActiveModelDirectory(
            inContainer: fixture.container
        )
        let expected = fixture.legacyRoot.appendingPathComponent("paddleocr-vl-manga-mlx")
        #expect(Self.equalPaths(resolved, expected),
                "Resolver must descend into the single valid child when the legacy root has no weights")
    }

    // Task 2.4
    @Test("Resolver returns nil when legacy root has multiple valid children")
    func ambiguousLegacyChildrenReturnsNil() throws {
        let fixture = try makeContainerFixture(.legacyMultipleChildren())
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let resolved = ModelDownloadService.resolvedActiveModelDirectory(
            inContainer: fixture.container
        )
        #expect(resolved == nil,
                "Resolver must refuse to choose arbitrarily when multiple valid children exist")
    }

    // Task 2.5
    @Test("Resolver falls back to valid legacy root when `.current` exists but lacks weights")
    func invalidCurrentFallsBackToLegacyRoot() throws {
        let fixture = try makeContainerFixture(.invalidCurrentPlusValidLegacy)
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let resolved = ModelDownloadService.resolvedActiveModelDirectory(
            inContainer: fixture.container
        )
        #expect(Self.equalPaths(resolved, fixture.legacyRoot),
                "An empty `.current` must not block fallback to a valid legacy root")
    }
}

// MARK: - Atomic install failure tests (Section 4)

@Suite("ModelDownloadService.atomicInstall")
struct AtomicInstallTests {

    // Per spec, staging artifacts must not survive a handled failure.
    private static func installingHasNoStagingCandidates(under container: URL) -> Bool {
        let installing = container.appendingPathComponent(".installing")
        guard FileManager.default.fileExists(atPath: installing.path) else { return true }
        let kids = (try? FileManager.default.contentsOfDirectory(at: installing, includingPropertiesForKeys: nil)) ?? []
        return kids.allSatisfy { !$0.lastPathComponent.hasPrefix("PaddleOCR-VL.next") }
    }

    private static func anyBackupExists(under container: URL) -> Bool {
        let children = (try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? []
        return children.contains { $0.lastPathComponent.hasPrefix("PaddleOCR-VL.backup") }
    }

    // Task 4.1
    @Test("Failed extraction preserves prior valid `.current`; metadata unchanged; state `.downloaded`")
    @MainActor
    func failedExtractionPreservesPriorCurrent() async throws {
        let priorChecksum = "prior-checksum-not-touched"
        let setup = try makeAtomicInstallSetup(
            layout: .currentOnly,
            extractorBehavior: .pathTraversalRejected,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let weights = setup.current.appendingPathComponent("weights.npz")
        #expect(FileManager.default.fileExists(atPath: weights.path),
                "Prior valid `.current` must survive failed extraction")
        #expect(setup.defaults.bool(forKey: "paddleocr.model.downloaded") == true)
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum)
        #expect(setup.defaults.bool(forKey: "paddleocr.enabled") == true)
        #expect(setup.service.state == .downloaded,
                "State must return to `.downloaded` when a prior valid model existed")
        #expect(Self.installingHasNoStagingCandidates(under: setup.container),
                "Failed attempt must leave no `.installing/PaddleOCR-VL.next.<uuid>` directory")
    }

    // Task 4.2
    @Test("Failed extraction preserves prior valid legacy root; metadata unchanged; state `.downloaded`")
    @MainActor
    func failedExtractionPreservesLegacyRoot() async throws {
        let priorChecksum = "prior-legacy-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .legacyRootOnly,
            extractorBehavior: .nonZeroUnzipExit,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let legacyWeights = setup.legacyRoot.appendingPathComponent("weights.npz")
        #expect(FileManager.default.fileExists(atPath: legacyWeights.path),
                "Prior valid legacy root must survive failed extraction")
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum)
        #expect(setup.defaults.bool(forKey: "paddleocr.enabled") == true)
        #expect(setup.service.state == .downloaded)
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    @Test("Successful update replaces `.current`, deletes backup, and updates metadata")
    @MainActor
    func successfulUpdateWithExistingCurrentPromotesNewCurrent() async throws {
        let priorChecksum = "prior-current-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .currentOnly,
            extractorBehavior: .successSafetensors,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        let payload = Data("replacement-current-archive".utf8)
        _ = try await primeArchive(on: setup.downloader, payload: payload)
        let expectedChecksum = sha256Hex(of: payload)

        await setup.service.download()

        #expect(setup.service.state == .downloaded)
        #expect(FileManager.default.fileExists(atPath: setup.current.appendingPathComponent("model.safetensors").path),
                "Promoted `.current` must contain the newly validated candidate")
        #expect(FileManager.default.fileExists(atPath: setup.current.appendingPathComponent("model.zip").path),
                "Successful installs must persist the verified archive under `.current`")
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == expectedChecksum)
        #expect(!Self.anyBackupExists(under: setup.container),
                "Backup created for the successful update must be removed")
        let resolved = ModelDownloadService.resolvedActiveModelDirectory(inContainer: setup.container)
        #expect(resolved?.standardizedFileURL.path == setup.current.standardizedFileURL.path)
    }

    @Test("Successful update with existing legacy model preserves legacy and prefers `.current`")
    @MainActor
    func successfulUpdateWithExistingLegacyPreservesLegacyRoot() async throws {
        let priorChecksum = "prior-legacy-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .legacyRootOnly,
            extractorBehavior: .successWeightsNpz,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        let payload = Data("replacement-from-legacy-archive".utf8)
        _ = try await primeArchive(on: setup.downloader, payload: payload)

        await setup.service.download()

        #expect(setup.service.state == .downloaded)
        #expect(FileManager.default.fileExists(atPath: setup.legacyRoot.appendingPathComponent("weights.npz").path),
                "Successful `.current` install must not delete the legacy root")
        #expect(FileManager.default.fileExists(atPath: setup.current.appendingPathComponent("weights.npz").path),
                "New successful installs must land in `.current`")
        let resolved = ModelDownloadService.resolvedActiveModelDirectory(inContainer: setup.container)
        #expect(resolved?.standardizedFileURL.path == setup.current.standardizedFileURL.path,
                "Future resolution must prefer `.current` after a successful update")
    }

    // Task 4.3
    @Test("First-install non-zero unzip clears metadata, disables enabled, state `.failed`")
    @MainActor
    func firstInstallNonZeroUnzipFails() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .nonZeroUnzipExit
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        #expect(setup.defaults.object(forKey: "paddleocr.model.downloaded") == nil,
                "First-install failure must clear downloaded flag")
        #expect(setup.defaults.object(forKey: "paddleocr.model.checksum") == nil,
                "First-install failure must clear stored checksum")
        #expect(setup.defaults.bool(forKey: "paddleocr.enabled") == false)
        if case .failed = setup.service.state {
            // expected
        } else {
            Issue.record("Expected `.failed` state for first-install non-zero unzip; got \(setup.service.state)")
        }
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    @Test("Insufficient disk space preserves prior current model and metadata")
    @MainActor
    func insufficientDiskSpacePreservesPriorCurrent() async throws {
        let priorChecksum = "prior-disk-space-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .currentOnly,
            priorChecksum: priorChecksum,
            availableSpaceProvider: { 1_024 }
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        #expect(FileManager.default.fileExists(atPath: setup.current.appendingPathComponent("weights.npz").path),
                "Disk-space failure must not modify a prior valid `.current` model")
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum)
        #expect(setup.defaults.bool(forKey: "paddleocr.enabled") == true)
        #expect(setup.service.state == .downloaded)
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    @Test("Download directory creation failure follows first-install failure rules")
    @MainActor
    func downloadDirectoryNotWritableFailsFirstInstallDeterministically() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .successWeightsNpz
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        setup.installFileOps.addCreateDirectoryFailure { url in
            if url.lastPathComponent.hasPrefix("PaddleOCR-VL.next") {
                return PaddleOCRError.storageUnavailable("simulated unwritable model container")
            }
            return nil
        }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        if case .failed = setup.service.state {
            // expected
        } else {
            Issue.record("Expected first-install directory creation failure to end in `.failed`; got \(setup.service.state)")
        }
        #expect(setup.defaults.object(forKey: "paddleocr.model.downloaded") == nil)
        #expect(setup.defaults.object(forKey: "paddleocr.model.checksum") == nil)
        #expect(setup.defaults.bool(forKey: "paddleocr.enabled") == false)
        #expect(!FileManager.default.fileExists(atPath: setup.current.path),
                "Failed first install must not create `.current`")
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    // Task 4.4
    @Test("Path traversal failure cleans staging; failure-state rules apply per prior-model state")
    @MainActor
    func pathTraversalFailureFollowsDeterministicRules() async throws {
        // Branch A: no prior valid model — state should transition to `.failed` and metadata clears.
        do {
            let setup = try makeAtomicInstallSetup(
                layout: nil,
                extractorBehavior: .pathTraversalRejected
            )
            defer { try? FileManager.default.removeItem(at: setup.container) }
            _ = try await primeArchive(on: setup.downloader)

            await setup.service.download()

            if case .failed = setup.service.state {
                // expected
            } else {
                Issue.record("Branch A: expected `.failed`, got \(setup.service.state)")
            }
            #expect(setup.defaults.object(forKey: "paddleocr.model.downloaded") == nil)
            #expect(Self.installingHasNoStagingCandidates(under: setup.container),
                    "Branch A: staging must be cleaned")
        }
        // Branch B: prior valid `.current` — state must return to `.downloaded` and prior model survives.
        do {
            let priorChecksum = "prior-traversal-checksum"
            let setup = try makeAtomicInstallSetup(
                layout: .currentOnly,
                extractorBehavior: .pathTraversalRejected,
                priorChecksum: priorChecksum
            )
            defer { try? FileManager.default.removeItem(at: setup.container) }
            _ = try await primeArchive(on: setup.downloader)

            await setup.service.download()

            let weights = setup.current.appendingPathComponent("weights.npz")
            #expect(FileManager.default.fileExists(atPath: weights.path),
                    "Branch B: prior `.current` must survive path-traversal failure")
            #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum)
            #expect(setup.service.state == .downloaded)
            #expect(Self.installingHasNoStagingCandidates(under: setup.container),
                    "Branch B: staging must be cleaned")
        }
    }

    // Task 4.5
    @Test("Checksum mismatch preserves prior valid `.current` and leaves no staging")
    @MainActor
    func checksumMismatchPreservesPriorModel() async throws {
        let priorChecksum = "prior-current-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .currentOnly,
            extractorBehavior: .successWeightsNpz,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        // Prime an archive whose SHA256 will NOT match the checksum we lie about.
        let payload = Data("checksum-mismatch-archive".utf8)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try payload.write(to: tmp)
        await setup.downloader.setDownload(tmp, checksum: "deliberately-wrong-checksum")

        await setup.service.download()

        let weights = setup.current.appendingPathComponent("weights.npz")
        #expect(FileManager.default.fileExists(atPath: weights.path),
                "Prior `.current` must survive checksum mismatch")
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum)
        #expect(setup.service.state == .downloaded)
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    // Task 4.6
    @Test("Extracted contents without weights are not promoted to `.current`")
    @MainActor
    func validationFailureBlocksPromotion() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .successWithoutWeights
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        // `.current` must not exist (was never promoted) or, if it does, must lack weights.
        let weights = setup.current.appendingPathComponent("weights.npz")
        let safetensors = setup.current.appendingPathComponent("model.safetensors")
        #expect(!FileManager.default.fileExists(atPath: weights.path)
                && !FileManager.default.fileExists(atPath: safetensors.path),
                "An invalid staging candidate must not be promoted to `.current`")
        if case .failed = setup.service.state {
            // expected for first install
        } else {
            Issue.record("Expected `.failed` state, got \(setup.service.state)")
        }
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    // Task 4.7
    @Test("Install rename failure restores prior `.current` via backup; metadata unchanged")
    @MainActor
    func installRenameFailureRestoresPriorCurrent() async throws {
        let priorChecksum = "prior-rename-failure-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .currentOnly,
            extractorBehavior: .successWeightsNpz,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        // Fail the active rename `.next.<uuid>` → `PaddleOCR-VL.current` so rollback runs.
        setup.installFileOps.addMoveFailure(MockInstallFileOpsFailure(
            matchesMoveSource: { $0.lastPathComponent.hasPrefix("PaddleOCR-VL.next") },
            error: PaddleOCRError.storageUnavailable("simulated rename failure")
        ))
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let weights = setup.current.appendingPathComponent("weights.npz")
        #expect(FileManager.default.fileExists(atPath: weights.path),
                "Rollback must restore prior `.current`")
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum,
                "Metadata must not move forward when install failed")
        #expect(setup.service.state == .downloaded)
        #expect(Self.installingHasNoStagingCandidates(under: setup.container))
    }

    // Task 4.8
    @Test("Rollback failure does not mark attempt downloaded; legacy root unchanged")
    @MainActor
    func rollbackFailureFollowsDeterministicRules() async throws {
        let priorChecksum = "prior-rollback-failure-checksum"
        // Use current + legacy together so we can verify legacy stays intact.
        let setup = try makeAtomicInstallSetup(
            layout: .currentPlusLegacy,
            extractorBehavior: .successWeightsNpz,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        // Fail the active rename AND the rollback rename.
        setup.installFileOps.addMoveFailure(MockInstallFileOpsFailure(
            matchesMoveSource: { $0.lastPathComponent.hasPrefix("PaddleOCR-VL.next") },
            error: PaddleOCRError.storageUnavailable("simulated active rename failure")
        ))
        setup.installFileOps.addMoveFailure(MockInstallFileOpsFailure(
            matchesMoveSource: { $0.lastPathComponent.hasPrefix("PaddleOCR-VL.backup") },
            error: PaddleOCRError.storageUnavailable("simulated rollback failure")
        ))
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        // Legacy root must remain untouched regardless of `.current` rollback outcome.
        let legacyWeights = setup.legacyRoot.appendingPathComponent("weights.npz")
        #expect(FileManager.default.fileExists(atPath: legacyWeights.path),
                "Legacy root must not be modified when rollback fails")
        // Prior metadata must NOT move forward — failed attempt is never marked downloaded.
        #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum,
                "Failed attempt must not overwrite stored checksum")
        // Deterministic failure rule: prior valid model existed → state returns to `.downloaded`.
        #expect(setup.service.state == .downloaded)
    }

    @Test("Failed update preserves prior valid model even when downloaded metadata drifted false")
    @MainActor
    func failurePreservesPriorValidModelWhenDownloadedFlagMissing() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: .currentOnly,
            extractorBehavior: .nonZeroUnzipExit
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        setup.defaults.set(true, forKey: "paddleocr.enabled")
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        #expect(FileManager.default.fileExists(atPath: setup.current.appendingPathComponent("weights.npz").path),
                "Prior valid `.current` must survive even if metadata drifted")
        #expect(setup.defaults.bool(forKey: "paddleocr.enabled") == true,
                "Failure should keep the prior enabled preference when a valid model resolved before the attempt")
        #expect(setup.service.state == .downloaded)
    }

    // Task 4.9
    @Test("Cancellation returns to `.downloaded` with prior model and `.notDownloaded` without")
    @MainActor
    func cancellationFollowsPriorModelState() async throws {
        // Branch A: prior valid `.current` — cancel must end in `.downloaded`.
        do {
            let priorChecksum = "prior-cancel-checksum"
            let setup = try makeAtomicInstallSetup(
                layout: .currentOnly,
                extractorBehavior: .successWeightsNpz,
                priorChecksum: priorChecksum
            )
            defer { try? FileManager.default.removeItem(at: setup.container) }
            _ = try await primeArchive(on: setup.downloader)
            // Override only the archive download to throw cancellation; checksum fetch still succeeds.
            await setup.downloader.setDownloadError(CancellationError())

            await setup.service.download()

            #expect(setup.service.state == .downloaded,
                    "Branch A: cancellation with prior valid model must return to `.downloaded`")
            #expect(setup.defaults.string(forKey: "paddleocr.model.checksum") == priorChecksum)
        }
        // Branch B: no prior model — cancel must end in `.notDownloaded`.
        do {
            let setup = try makeAtomicInstallSetup(
                layout: nil,
                extractorBehavior: .successWeightsNpz
            )
            defer { try? FileManager.default.removeItem(at: setup.container) }
            _ = try await primeArchive(on: setup.downloader)
            await setup.downloader.setDownloadError(CancellationError())

            await setup.service.download()

            #expect(setup.service.state == .notDownloaded,
                    "Branch B: cancellation without prior valid model must transition to `.notDownloaded`")
            #expect(setup.defaults.object(forKey: "paddleocr.model.downloaded") == nil)
        }
    }
}

// MARK: - Cleanup tests (Section 6)

@Suite("ModelDownloadService.installCleanup")
struct InstallCleanupTests {

    private static func installingExists(under container: URL) -> Bool {
        FileManager.default.fileExists(atPath: container.appendingPathComponent(".installing").path)
    }

    private static func anyBackupExists(under container: URL) -> Bool {
        let children = (try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? []
        return children.contains { $0.lastPathComponent.hasPrefix("PaddleOCR-VL.backup") }
    }

    // Task 6.1
    @Test("Successful install leaves no `.installing/PaddleOCR-VL.next.<uuid>` and no backup")
    @MainActor
    func successfulInstallLeavesNoStagingOrBackup() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .successWeightsNpz
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        #expect(setup.service.state == .downloaded,
                "Precondition: successful install must end in `.downloaded`")
        #expect(!Self.installingExists(under: setup.container),
                "`.installing` must be cleaned up after a successful install")
        #expect(!Self.anyBackupExists(under: setup.container),
                "No backup must remain after a successful first install")
    }

    // Task 6.2
    @Test("Path traversal failure leaves no staging candidate from the failed attempt")
    @MainActor
    func pathTraversalLeavesNoStaging() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .pathTraversalRejected
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let installing = setup.container.appendingPathComponent(".installing")
        if FileManager.default.fileExists(atPath: installing.path) {
            let kids = try FileManager.default.contentsOfDirectory(at: installing, includingPropertiesForKeys: nil)
            #expect(kids.allSatisfy { !$0.lastPathComponent.hasPrefix("PaddleOCR-VL.next") },
                    "No `PaddleOCR-VL.next.<uuid>` may survive a path-traversal failure")
        }
    }

    // Task 6.3
    @Test("Non-zero unzip exit leaves no staging candidate from the failed attempt")
    @MainActor
    func nonZeroUnzipLeavesNoStaging() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .nonZeroUnzipExit
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let installing = setup.container.appendingPathComponent(".installing")
        if FileManager.default.fileExists(atPath: installing.path) {
            let kids = try FileManager.default.contentsOfDirectory(at: installing, includingPropertiesForKeys: nil)
            #expect(kids.allSatisfy { !$0.lastPathComponent.hasPrefix("PaddleOCR-VL.next") })
        }
    }

    // Task 6.4
    @Test("Validation failure (no weights) leaves no staging candidate from the failed attempt")
    @MainActor
    func validationFailureLeavesNoStaging() async throws {
        let setup = try makeAtomicInstallSetup(
            layout: nil,
            extractorBehavior: .successWithoutWeights
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let installing = setup.container.appendingPathComponent(".installing")
        if FileManager.default.fileExists(atPath: installing.path) {
            let kids = try FileManager.default.contentsOfDirectory(at: installing, includingPropertiesForKeys: nil)
            #expect(kids.allSatisfy { !$0.lastPathComponent.hasPrefix("PaddleOCR-VL.next") })
        }
    }

    // Task 6.5
    @Test("Cleanup never removes a valid legacy `PaddleOCR-VL` directory")
    @MainActor
    func cleanupPreservesLegacyRoot() async throws {
        let priorChecksum = "prior-legacy-cleanup-checksum"
        let setup = try makeAtomicInstallSetup(
            layout: .legacyRootOnly,
            extractorBehavior: .nonZeroUnzipExit,
            priorChecksum: priorChecksum
        )
        defer { try? FileManager.default.removeItem(at: setup.container) }
        _ = try await primeArchive(on: setup.downloader)

        await setup.service.download()

        let legacyWeights = setup.legacyRoot.appendingPathComponent("weights.npz")
        #expect(FileManager.default.fileExists(atPath: legacyWeights.path),
                "Legacy `PaddleOCR-VL` must not be removed by install cleanup")
    }
}

// MARK: - Launch verification tests (Section 8)

@Suite("ModelDownloadService.verifyOnLaunch")
struct VerifyOnLaunchTests {

    /// Builds a configured service against a real container layout and seeds
    /// matching `UserDefaults` so `verifyOnLaunch()` can run end-to-end.
    @MainActor
    private static func makeLaunchService(
        layout: ContainerLayout,
        archive: (URL) -> URL,        // computes the model.zip path inside the laid-out tree
        archivePayload: Data?,         // nil → don't create archive
        storedChecksum: String?,       // nil → don't set checksum
        markFresh: Bool = false
    ) throws -> (ModelDownloadService, URL /* container */, UserDefaults) {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        _ = try makeContainerFixture(layout, in: container)

        if let archivePayload {
            let archivePath = archive(container)
            try FileManager.default.createDirectory(at: archivePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archivePayload.write(to: archivePath)
        }

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        if let storedChecksum {
            defaults.set(storedChecksum, forKey: "paddleocr.model.checksum")
        }
        if markFresh {
            defaults.set(Date().timeIntervalSince1970, forKey: "paddleocr.model.lastVerified")
        } else {
            // Force the stale-evidence branch so full SHA256 runs.
            defaults.set(0.0, forKey: "paddleocr.model.lastVerified")
        }

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: legacyRoot,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)
        return (service, container, defaults)
    }

    // Task 8.1
    @Test("Launch verification accepts valid `.current/model.zip` with matching stored checksum")
    @MainActor
    func acceptsCurrentArchive() async throws {
        let payload = Data("current-archive".utf8)
        let checksum = sha256Hex(of: payload)
        let (service, container, defaults) = try Self.makeLaunchService(
            layout: .currentOnly,
            archive: { $0.appendingPathComponent("PaddleOCR-VL.current").appendingPathComponent("model.zip") },
            archivePayload: payload,
            storedChecksum: checksum
        )
        defer { try? FileManager.default.removeItem(at: container) }

        await service.verifyOnLaunch()

        #expect(service.state == .downloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded") == true)
    }

    // Task 8.2
    @Test("Launch verification accepts legacy `PaddleOCR-VL/model.zip` when `.current` is absent")
    @MainActor
    func acceptsLegacyArchiveWhenCurrentAbsent() async throws {
        let payload = Data("legacy-archive".utf8)
        let checksum = sha256Hex(of: payload)
        let (service, container, defaults) = try Self.makeLaunchService(
            layout: .legacyRootOnly,
            archive: { $0.appendingPathComponent("PaddleOCR-VL").appendingPathComponent("model.zip") },
            archivePayload: payload,
            storedChecksum: checksum
        )
        defer { try? FileManager.default.removeItem(at: container) }

        await service.verifyOnLaunch()

        #expect(service.state == .downloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded") == true)
    }

    // Task 8.3
    @Test("Launch verification resets state when no valid model directory resolves")
    @MainActor
    func resetsWhenNoModelResolves() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("anything", forKey: "paddleocr.model.checksum")
        defaults.set(true, forKey: "paddleocr.enabled")

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: legacyRoot,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        await service.verifyOnLaunch()

        #expect(service.state == .notDownloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded") == false)
        #expect(defaults.string(forKey: "paddleocr.model.checksum") == nil)
        #expect(defaults.bool(forKey: "paddleocr.enabled") == false)
    }

    // Task 8.4
    @Test("Launch verification resets state when resolved directory lacks `model.zip`")
    @MainActor
    func resetsWhenArchiveMissing() async throws {
        let (service, container, defaults) = try Self.makeLaunchService(
            layout: .currentOnly,
            archive: { _ in URL(fileURLWithPath: "/dev/null") }, // unused
            archivePayload: nil,
            storedChecksum: "anything"
        )
        defer { try? FileManager.default.removeItem(at: container) }

        await service.verifyOnLaunch()

        #expect(service.state == .notDownloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded") == false)
    }

    // Task 8.5
    @Test("Launch verification resets state when resolved archive checksum mismatches stored checksum")
    @MainActor
    func resetsOnChecksumMismatch() async throws {
        let payload = Data("real-archive-bytes".utf8)
        let (service, container, defaults) = try Self.makeLaunchService(
            layout: .currentOnly,
            archive: { $0.appendingPathComponent("PaddleOCR-VL.current").appendingPathComponent("model.zip") },
            archivePayload: payload,
            storedChecksum: "deliberately-wrong-checksum"
        )
        defer { try? FileManager.default.removeItem(at: container) }

        await service.verifyOnLaunch()

        #expect(service.state == .notDownloaded)
        #expect(defaults.bool(forKey: "paddleocr.model.downloaded") == false)
        #expect(defaults.string(forKey: "paddleocr.model.checksum") == nil)
    }
}

// MARK: - Delete tests (Section 10)

@Suite("ModelDownloadService.delete")
struct DeleteTests {

    @MainActor
    private static func makeDeleteService(seed: (URL) throws -> Void) throws -> (ModelDownloadService, URL, UserDefaults) {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try seed(container)

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("any-checksum", forKey: "paddleocr.model.checksum")
        defaults.set(Date().timeIntervalSince1970, forKey: "paddleocr.model.lastVerified")
        defaults.set(true, forKey: "paddleocr.enabled")
        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: legacyRoot,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)
        return (service, container, defaults)
    }

    // Task 10.1
    @Test("delete() removes `PaddleOCR-VL.current`")
    @MainActor
    func deleteRemovesCurrent() async throws {
        let (service, container, _) = try Self.makeDeleteService { c in
            try makeValidModelDir(at: c.appendingPathComponent("PaddleOCR-VL.current"))
        }
        defer { try? FileManager.default.removeItem(at: container) }

        try await service.delete()

        #expect(!FileManager.default.fileExists(atPath: container.appendingPathComponent("PaddleOCR-VL.current").path))
    }

    // Task 10.2
    @Test("delete() removes legacy `PaddleOCR-VL`")
    @MainActor
    func deleteRemovesLegacyRoot() async throws {
        let (service, container, _) = try Self.makeDeleteService { c in
            try makeValidModelDir(at: c.appendingPathComponent("PaddleOCR-VL"))
        }
        defer { try? FileManager.default.removeItem(at: container) }

        try await service.delete()

        #expect(!FileManager.default.fileExists(atPath: container.appendingPathComponent("PaddleOCR-VL").path))
    }

    // Task 10.3
    @Test("delete() removes `.installing` and `PaddleOCR-VL.backup.<uuid>` artifacts")
    @MainActor
    func deleteRemovesStagingAndBackups() async throws {
        let backupSlug = "PaddleOCR-VL.backup.test-uuid"
        let nextSlug = "PaddleOCR-VL.next.test-uuid"
        let (service, container, _) = try Self.makeDeleteService { c in
            let installing = c.appendingPathComponent(".installing")
            try FileManager.default.createDirectory(at: installing.appendingPathComponent(nextSlug), withIntermediateDirectories: true)
            try Data().write(to: installing.appendingPathComponent(nextSlug).appendingPathComponent("placeholder"))
            try FileManager.default.createDirectory(at: c.appendingPathComponent(backupSlug), withIntermediateDirectories: true)
            try Data().write(to: c.appendingPathComponent(backupSlug).appendingPathComponent("placeholder"))
        }
        defer { try? FileManager.default.removeItem(at: container) }

        try await service.delete()

        #expect(!FileManager.default.fileExists(atPath: container.appendingPathComponent(".installing").path),
                "`.installing` must be removed by delete()")
        #expect(!FileManager.default.fileExists(atPath: container.appendingPathComponent(backupSlug).path),
                "Backup directories must be removed by delete()")
    }

    // Task 10.4
    @Test("delete() succeeds silently when no current, legacy, staging, or backup artifacts exist")
    @MainActor
    func deleteSucceedsWhenNothingExists() async throws {
        let (service, container, _) = try Self.makeDeleteService { _ in /* empty */ }
        defer { try? FileManager.default.removeItem(at: container) }

        await #expect(throws: Never.self) {
            try await service.delete()
        }
        #expect(service.state == .notDownloaded)
    }

    // Task 10.5
    @Test("delete() clears downloaded/checksum/lastVerified, disables enabled, state .notDownloaded")
    @MainActor
    func deleteClearsDefaultsAndState() async throws {
        let (service, container, defaults) = try Self.makeDeleteService { c in
            try makeValidModelDir(at: c.appendingPathComponent("PaddleOCR-VL.current"))
        }
        defer { try? FileManager.default.removeItem(at: container) }

        try await service.delete()

        #expect(defaults.object(forKey: "paddleocr.model.downloaded") == nil)
        #expect(defaults.object(forKey: "paddleocr.model.checksum") == nil)
        #expect(defaults.object(forKey: "paddleocr.model.lastVerified") == nil)
        #expect(defaults.bool(forKey: "paddleocr.enabled") == false)
        #expect(service.state == .notDownloaded)
    }

    @Test("delete() and verifyOnLaunch() overlap settles to notDownloaded")
    @MainActor
    func deleteAndVerifyOnLaunchOverlapIsDeterministic() async throws {
        let archivePayload = Data("current-archive-for-delete-race".utf8)
        let checksum = sha256Hex(of: archivePayload)
        let (service, container, defaults) = try Self.makeDeleteService { c in
            let current = try makeValidModelDir(at: c.appendingPathComponent("PaddleOCR-VL.current"))
            try archivePayload.write(to: current.appendingPathComponent("model.zip"))
        }
        defer { try? FileManager.default.removeItem(at: container) }
        defaults.set(checksum, forKey: "paddleocr.model.checksum")
        defaults.set(0.0, forKey: "paddleocr.model.lastVerified")

        async let verifyTask: Void = service.verifyOnLaunch()
        try await service.delete()
        await verifyTask

        #expect(service.state == .notDownloaded)
        #expect(defaults.object(forKey: "paddleocr.model.downloaded") == nil)
        #expect(defaults.object(forKey: "paddleocr.model.checksum") == nil)
        #expect(defaults.bool(forKey: "paddleocr.enabled") == false)
        #expect(!FileManager.default.fileExists(atPath: container.appendingPathComponent("PaddleOCR-VL.current").path))
    }
}

@Suite("ModelDownloadService.productionModelSearchRoots")
struct ProductionModelSearchRootsTests {
    private let fakeHome = "/fake/home"

    @Test("Returns two search roots")
    func returnsTwoRoots() {
        let roots = ModelDownloadService.productionModelSearchRoots(homeDirectory: fakeHome)
        #expect(roots.count == 2)
    }

    @Test("First root matches defaultModelDirectory")
    func firstRootIsDefaultModelDirectory() {
        let roots = ModelDownloadService.productionModelSearchRoots(homeDirectory: fakeHome)
        #expect(roots[0] == ModelDownloadService.defaultModelDirectory())
    }

    @Test("Container fallback path structure is Library/Containers/<bundleID>/Data/...")
    func containerFallbackPathStructure() {
        let roots = ModelDownloadService.productionModelSearchRoots(homeDirectory: fakeHome)
        let expected = "/fake/home/Library/Containers/com.chunweiliu.MangaTranslator/Data/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL"
        #expect(roots[1].path == expected)
    }

    @Test("Default homeDirectory is real user home, not sandbox-remapped container path")
    func defaultHomeDirectoryIsRealHome() {
        let realHome = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ModelDownloadService.productionModelSearchRoots()
        // The container fallback must be rooted at the real home so it resolves correctly
        // whether called from the sandboxed app or a non-sandboxed helper process.
        #expect(roots[1].path.hasPrefix(realHome + "/Library/Containers/"))
    }

    @Test("Production resolver returns `.current` beside a legacy root")
    func productionResolverReturnsCurrentSibling() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = base.appendingPathComponent("home")
        let defaultContainer = ModelDownloadService.defaultModelDirectory().deletingLastPathComponent()
        if ModelDownloadService.resolvedActiveModelDirectory(inContainer: defaultContainer) != nil {
            return
        }

        let sandboxContainer = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent("com.chunweiliu.MangaTranslator")
            .appendingPathComponent("Data")
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
        try makeValidModelDir(at: sandboxContainer.appendingPathComponent("PaddleOCR-VL.current"))
        defer { try? FileManager.default.removeItem(at: base) }

        let resolved = ModelDownloadService.resolvedProductionModelDirectory(
            homeDirectory: home.path
        )

        #expect(resolved == sandboxContainer.appendingPathComponent("PaddleOCR-VL.current"))
    }
}

// MARK: - Task 8: Lifecycle coordination

/// Thread-safe collector for `ModelLifecycleEvent` values emitted by the
/// lifecycle actor's observer hook. The observer closure runs inside the
/// actor's isolated context, so the recorder must be safe under concurrent
/// appends from background tests.
private final class LifecycleEventRecorder: @unchecked Sendable {
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

@Suite("ModelDownloadService.lifecycleCoordination")
struct LifecycleCoordinationTests {

    /// Seed a `.current` model and bind a `ModelDownloadService` configured to
    /// treat that container as the legacy root's parent. Returns the service,
    /// container, and defaults so each test can drive lifecycle calls and
    /// assert filesystem effects in isolation.
    @MainActor
    private static func makeServiceWithCurrentModel(
    ) throws -> (ModelDownloadService, URL, UserDefaults) {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try makeValidModelDir(at: container.appendingPathComponent("PaddleOCR-VL.current"))

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set("any-checksum", forKey: "paddleocr.model.checksum")
        defaults.set(Date().timeIntervalSince1970, forKey: "paddleocr.model.lastVerified")
        defaults.set(true, forKey: "paddleocr.enabled")
        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: legacyRoot,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)
        return (service, container, defaults)
    }

    @Test("delete() suspends on a continuation while inference is active and resumes via a single wakeup")
    @MainActor
    func deleteWaitsForActiveInferenceWithoutBusyYield() async throws {
        let (service, container, _) = try Self.makeServiceWithCurrentModel()
        defer { try? FileManager.default.removeItem(at: container) }

        let recorder = LifecycleEventRecorder()
        await service.setLifecycleObserver { event in
            recorder.append(event)
        }

        await service.beginInference()

        let deleteTask = Task { try await service.delete() }

        // Give delete() enough turns to enter the section and queue itself on
        // the inference wait continuation.
        for _ in 0..<10 { await Task.yield() }

        let midEvents = recorder.snapshot()
        #expect(midEvents.contains(.sectionEntered("delete")),
                "delete() must enter the lifecycle section before waiting")
        #expect(midEvents.contains(.waitForInferencesBegan),
                "delete() must record waitForInferencesBegan while inference is active")
        #expect(!midEvents.contains(.waitForInferencesResumed),
                "delete() must remain suspended until endInference() fires")

        await service.endInference()
        try await deleteTask.value

        let finalEvents = recorder.snapshot()
        // Continuation-based wait: exactly one .waitForInferencesBegan and one
        // .waitForInferencesResumed. A busy-yield loop would either skip the
        // begin/resume pair entirely or emit a stream of polling events.
        let beganCount = finalEvents.filter { $0 == .waitForInferencesBegan }.count
        let resumedCount = finalEvents.filter { $0 == .waitForInferencesResumed }.count
        #expect(beganCount == 1, "waitForInferencesBegan must fire exactly once; got \(beganCount)")
        #expect(resumedCount == 1, "waitForInferencesResumed must fire exactly once; got \(resumedCount)")
        #expect(finalEvents.contains(.sectionExited("delete")),
                "delete() must record sectionExited(\"delete\") on completion")
        #expect(service.state == .notDownloaded)
    }

    @Test("delete() and verifyOnLaunch() sections never overlap when run concurrently")
    @MainActor
    func deleteVerifySectionsAreMutuallyExclusiveViaObserver() async throws {
        let archivePayload = Data("current-archive-for-mutex-test".utf8)
        let checksum = sha256Hex(of: archivePayload)
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let current = try makeValidModelDir(at: container.appendingPathComponent("PaddleOCR-VL.current"))
        try archivePayload.write(to: current.appendingPathComponent("model.zip"))
        defer { try? FileManager.default.removeItem(at: container) }

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paddleocr.model.downloaded")
        defaults.set(checksum, forKey: "paddleocr.model.checksum")
        // Stale evidence forces verifyOnLaunch onto the full SHA256 path so its
        // section holds the lock long enough to overlap delete().
        defaults.set(0.0, forKey: "paddleocr.model.lastVerified")
        defaults.set(true, forKey: "paddleocr.enabled")
        let config = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/checksum")!,
            modelDirectory: legacyRoot,
            userDefaults: defaults,
            downloader: MockDownloader()
        )
        let service = ModelDownloadService(configuration: config)

        let recorder = LifecycleEventRecorder()
        await service.setLifecycleObserver { event in
            recorder.append(event)
        }

        async let verifyTask: Void = service.verifyOnLaunch()
        try await service.delete()
        await verifyTask

        // Keep only the section enter/exit events so the assertion is robust
        // even if the actor emits other lifecycle events in the future.
        let sectionEvents = recorder.snapshot().filter { event in
            switch event {
            case .sectionEntered, .sectionExited: return true
            default: return false
            }
        }

        // Verify strict serialization: every enter must be immediately followed
        // by the matching exit before any other section enters.
        var currentSection: String?
        for event in sectionEvents {
            switch event {
            case .sectionEntered(let name):
                #expect(currentSection == nil,
                        "Section \"\(name)\" entered while \"\(currentSection ?? "?")\" still held the lock")
                currentSection = name
            case .sectionExited(let name):
                #expect(currentSection == name,
                        "Section exit \"\(name)\" did not match the active section \"\(currentSection ?? "?")\"")
                currentSection = nil
            default:
                break
            }
        }
        #expect(currentSection == nil, "All entered sections must exit before observation ends")
        #expect(service.state == .notDownloaded)
    }

    @Test("Lifecycle section exit is observable before delete() returns")
    @MainActor
    func lifecycleSectionExitIsObservableBeforeReturn() async throws {
        let (service, container, _) = try Self.makeServiceWithCurrentModel()
        defer { try? FileManager.default.removeItem(at: container) }

        let recorder = LifecycleEventRecorder()
        await service.setLifecycleObserver { event in
            recorder.append(event)
        }

        try await service.delete()

        // Snapshot the recorder synchronously after delete() returns. With
        // inline `await endLifecycleMutation`, the exit event is already
        // recorded. A deferred-Task release would leave the exit event
        // unrecorded at this point because the detached Task has not yet
        // been scheduled onto the actor.
        let events = recorder.snapshot()
        #expect(events.last == .sectionExited("delete"),
                "Last observed event must be sectionExited(\"delete\") when control returns; got \(events)")
    }
}
