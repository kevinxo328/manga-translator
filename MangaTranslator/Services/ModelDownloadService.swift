import Foundation
import Combine
import CryptoKit
import os

// MARK: - Downloader protocol for testability

protocol ModelDownloading: Sendable {
    func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL
    func fetchString(from url: URL) async throws -> String
}

// MARK: - Inference coordination seam

/// Lets the OCR routing layer register active inference so lifecycle mutations
/// (delete, reinstall) wait for in-flight model work. `ModelDownloadService`
/// satisfies this via its lifecycle actor; tests can inject recording fakes.
protocol ModelInferenceCoordinating: Sendable {
    func beginInference() async
    func endInference() async
}

// MARK: - Archive extraction seam

/// Extracts a verified zip archive into a previously-empty staging candidate.
/// Implementations MUST reject `/usr/bin/unzip` non-zero termination and any
/// resolved entry path that escapes the staging candidate. Used to isolate
/// extraction from the install transaction so tests can simulate failures
/// without crafting real malicious archives.
protocol ModelArchiveExtracting: Sendable {
    func extract(archive: URL, into candidate: URL) throws
}

struct DefaultArchiveExtractor: ModelArchiveExtracting {
    // Use the project's `ArchiveExtractor` for model archives so we get
    // `zipinfo`-based pre-extraction validation (absolute-path/`..`/destination-
    // escape rejection, symlink+special-entry rejection) on top of the same
    // post-extraction containment check. Doing only post-validation here would
    // miss entries that `/usr/bin/unzip` writes outside the candidate, since
    // they wouldn't appear when enumerating the candidate.
    //
    // The default ArchiveExtractor.Limits cap a single file at 25 MB and the
    // total at 500 MB. The PaddleOCR-VL model archive can exceed those limits,
    // so we widen them here while keeping the file-count cap as a sanity guard.
    func extract(archive: URL, into candidate: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)

        var limits = ArchiveExtractor.Limits()
        limits.maxSingleFileBytes = 4 * 1024 * 1024 * 1024  // 4 GiB
        limits.maxTotalBytes = 8 * 1024 * 1024 * 1024       // 8 GiB
        limits.maxFiles = 10_000

        do {
            try ArchiveExtractor.extract(archiveURL: archive, into: candidate, limits: limits)
        } catch {
            // Map any extractor-specific failure (path traversal, non-zero unzip
            // exit, post-validation escape) to the model-install verifyFailed.
            throw PaddleOCRError.verifyFailed
        }
    }
}

// MARK: - Install file-op seam

/// Filesystem operations the install transaction uses for active rename and
/// rollback. Injecting this seam lets tests simulate rename or rollback
/// failures deterministically without needing platform-specific permission
/// tricks.
protocol ModelInstallFileOps: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

struct DefaultModelInstallFileOps: ModelInstallFileOps {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}

// MARK: - Configuration

struct ModelDownloadConfiguration {
    let modelURL: URL
    let checksumURL: URL
    let modelDirectory: URL
    let userDefaults: UserDefaults
    let downloader: any ModelDownloading
    let extractor: any ModelArchiveExtracting
    let installFileOps: any ModelInstallFileOps
    let availableSpaceProvider: @Sendable () -> Int64?

    init(
        modelURL: URL,
        checksumURL: URL,
        modelDirectory: URL,
        userDefaults: UserDefaults,
        downloader: any ModelDownloading,
        extractor: any ModelArchiveExtracting = DefaultArchiveExtractor(),
        installFileOps: any ModelInstallFileOps = DefaultModelInstallFileOps(),
        availableSpaceProvider: @escaping @Sendable () -> Int64? = {
            let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attrs?[.systemFreeSize] as? Int64
        }
    ) {
        self.modelURL = modelURL
        self.checksumURL = checksumURL
        self.modelDirectory = modelDirectory
        self.userDefaults = userDefaults
        self.downloader = downloader
        self.extractor = extractor
        self.installFileOps = installFileOps
        self.availableSpaceProvider = availableSpaceProvider
    }

    static var `default`: ModelDownloadConfiguration {
        let modelDir = ModelDownloadService.defaultModelDirectory()
        return ModelDownloadConfiguration(
            modelURL: URL(string: "https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx/resolve/main/model.zip")!,
            checksumURL: URL(string: "https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx/resolve/main/model.zip.sha256")!,
            modelDirectory: modelDir,
            userDefaults: .standard,
            downloader: URLSessionDownloader()
        )
    }

    // MARK: - Preview configurations

    static var previewNotDownloaded: ModelDownloadConfiguration {
        makePreview(downloaded: false, enabled: false)
    }

    static var previewDownloading: ModelDownloadConfiguration {
        makePreview(downloaded: false, enabled: false)
    }

    static var previewDownloadedEnabled: ModelDownloadConfiguration {
        makePreview(downloaded: true, enabled: true)
    }

    static var previewDownloadedDisabled: ModelDownloadConfiguration {
        makePreview(downloaded: true, enabled: false)
    }

    private static func makePreview(downloaded: Bool, enabled: Bool) -> ModelDownloadConfiguration {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        defaults.set(downloaded, forKey: "paddleocr.model.downloaded")
        defaults.set(enabled, forKey: "paddleocr.enabled")
        return ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.com/model.zip")!,
            checksumURL: URL(string: "https://example.com/model.zip.sha256")!,
            modelDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-model"),
            userDefaults: defaults,
            downloader: URLSessionDownloader()
        )
    }
}

// MARK: - UserDefaults keys

private enum DefaultsKey {
    static let downloaded = "paddleocr.model.downloaded"
    static let checksum = "paddleocr.model.checksum"
    static let lastVerified = "paddleocr.model.lastVerified"
    static let enabled = "paddleocr.enabled"
}

// MARK: - ModelDownloadManaging

@MainActor
protocol ModelDownloadManaging: AnyObject {
    var state: ModelDownloadState { get }
    var isPaddleOCREnabled: Bool { get }
}

// MARK: - ModelDownloadServicing (full mutation API for Settings UI)

@MainActor
protocol ModelDownloadServicing: ModelDownloadManaging {
    // Typed publishers carry the NEW value to avoid willSet timing issues.
    var statePublisher: AnyPublisher<ModelDownloadState, Never> { get }
    var enabledPublisher: AnyPublisher<Bool, Never> { get }
    func download() async
    func cancel()
    func delete() async throws
    func setEnabled(_ enabled: Bool)
}

// MARK: - ModelDownloadService

@MainActor
final class ModelDownloadService: ObservableObject, ModelDownloadServicing {
    @Published private(set) var state: ModelDownloadState
    @Published private(set) var paddleOCREnabled: Bool

    static let shared = ModelDownloadService()

    var isPaddleOCREnabled: Bool {
        state == .downloaded && paddleOCREnabled
    }

    var statePublisher: AnyPublisher<ModelDownloadState, Never> {
        $state.eraseToAnyPublisher()
    }

    var enabledPublisher: AnyPublisher<Bool, Never> {
        $paddleOCREnabled.eraseToAnyPublisher()
    }

    private let config: ModelDownloadConfiguration
    private var currentTask: Task<Void, Never>?
    private let lifecycleActor = ModelLifecycleActor()

    init(configuration: ModelDownloadConfiguration = .default) {
        self.config = configuration
        let downloaded = configuration.userDefaults.bool(forKey: DefaultsKey.downloaded)
        self.state = downloaded ? .downloaded : .notDownloaded
        self.paddleOCREnabled = configuration.userDefaults.bool(forKey: DefaultsKey.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard !enabled || state == .downloaded else { return }
        paddleOCREnabled = enabled
        config.userDefaults.set(enabled, forKey: DefaultsKey.enabled)
    }

    // MARK: - Public API

    func download() async {
        guard state != .downloading(progress: 0) else { return }
        if case .downloading = state { return }

        currentTask = Task {
            await performDownload()
        }
        await currentTask?.value
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        // The in-flight task's `catch is CancellationError` branch removes any
        // current-attempt `.next` candidate and empty `.installing` directory and
        // applies the deterministic failure-state rule. Settle state synchronously
        // from current evidence in case no task is running.
        let fm = FileManager.default
        let container = Self.modelContainer(forLegacyRoot: config.modelDirectory)
        let priorResolved = Self.resolvedActiveModelDirectory(inContainer: container, fileManager: fm)
        let priorDownloaded = config.userDefaults.bool(forKey: DefaultsKey.downloaded)
        if priorResolved != nil && priorDownloaded {
            state = .downloaded
        } else {
            state = .notDownloaded
        }
    }

    func delete() async throws {
        await lifecycleActor.beginLifecycleMutation(section: "delete")
        do {
            // Task 11.2 — wait for any active inference before mutating model artifacts.
            await lifecycleActor.waitForActiveInferences()

            let fm = FileManager.default
            let legacyRoot = config.modelDirectory
            let container = Self.modelContainer(forLegacyRoot: legacyRoot)
            let currentDir = container.appendingPathComponent("PaddleOCR-VL.current")
            let installingRoot = container.appendingPathComponent(".installing")

            // Task 11.1 — remove `.current`, legacy root, `.installing`, and any backup directories.
            // Task 11.3 — idempotent: only attempt removal when the target path exists.
            if fm.fileExists(atPath: currentDir.path) {
                try fm.removeItem(at: currentDir)
            }
            if fm.fileExists(atPath: legacyRoot.path) {
                try fm.removeItem(at: legacyRoot)
            }
            if fm.fileExists(atPath: installingRoot.path) {
                try fm.removeItem(at: installingRoot)
            }
            if let kids = try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil) {
                for kid in kids where kid.lastPathComponent.hasPrefix("PaddleOCR-VL.backup") {
                    try? fm.removeItem(at: kid)
                }
            }

            config.userDefaults.removeObject(forKey: DefaultsKey.downloaded)
            config.userDefaults.removeObject(forKey: DefaultsKey.checksum)
            config.userDefaults.removeObject(forKey: DefaultsKey.lastVerified)
            config.userDefaults.set(false, forKey: DefaultsKey.enabled)
            paddleOCREnabled = false
            // Task 11.4 — `delete()` always settles to `.notDownloaded`; concurrent
            // `verifyOnLaunch` either runs before delete clears artifacts (resolving
            // the now-absent model and resetting state) or after (no-op fast path).
            state = .notDownloaded
        } catch {
            // Release the lifecycle section inline so a subsequent caller does
            // not race against a detached release Task.
            await lifecycleActor.endLifecycleMutation(section: "delete")
            throw error
        }
        await lifecycleActor.endLifecycleMutation(section: "delete")
    }

    func verify() async -> Bool {
        let fm = FileManager.default
        let container = Self.modelContainer(forLegacyRoot: config.modelDirectory)
        guard let activeDir = Self.resolvedActiveModelDirectory(inContainer: container, fileManager: fm) else {
            return false
        }
        let archivePath = activeDir.appendingPathComponent("model.zip")
        guard fm.fileExists(atPath: archivePath.path) else { return false }

        let storedChecksum = config.userDefaults.string(forKey: DefaultsKey.checksum) ?? ""
        guard !storedChecksum.isEmpty else { return false }

        guard let computed = sha256(of: archivePath) else { return false }
        return computed == storedChecksum
    }

    func verifyOnLaunch() async {
        guard config.userDefaults.bool(forKey: DefaultsKey.downloaded) else { return }

        await lifecycleActor.beginLifecycleMutation(section: "verify")

        let fm = FileManager.default
        let container = Self.modelContainer(forLegacyRoot: config.modelDirectory)

        // Task 9.1 — resolve the active model directory before choosing the archive path.
        guard let activeDir = Self.resolvedActiveModelDirectory(inContainer: container, fileManager: fm) else {
            resetDownloadState()
            await lifecycleActor.endLifecycleMutation(section: "verify")
            return
        }
        let archivePath = activeDir.appendingPathComponent("model.zip")

        // Task 9.3 — clear state when the archive itself is missing.
        guard fm.fileExists(atPath: archivePath.path) else {
            resetDownloadState()
            await lifecycleActor.endLifecycleMutation(section: "verify")
            return
        }

        let storedChecksum = config.userDefaults.string(forKey: DefaultsKey.checksum) ?? ""
        if storedChecksum.isEmpty {
            resetDownloadState()
            await lifecycleActor.endLifecycleMutation(section: "verify")
            return
        }

        // Task 9.4 — fast-path only when resolution + archive path are valid AND evidence is fresh.
        let lastVerified = config.userDefaults.double(forKey: DefaultsKey.lastVerified)
        let now = Date().timeIntervalSince1970
        let isFresh = (now - lastVerified) < (86400 * 7)
        if isFresh {
            state = .downloaded
            await lifecycleActor.endLifecycleMutation(section: "verify")
            return
        }

        // Task 9.2 — full SHA256 on the resolved archive when evidence is stale.
        let valid = await Task.detached(priority: .background) { [archivePath, storedChecksum] in
            guard let computed = Self.sha256Static(of: archivePath) else { return false }
            return computed == storedChecksum
        }.value

        if !valid {
            try? fm.removeItem(at: archivePath)
            resetDownloadState()
        } else {
            state = .downloaded
        }
        await lifecycleActor.endLifecycleMutation(section: "verify")
    }

    // MARK: - Test-only lifecycle observation

    /// Attaches an observer to the lifecycle actor for test introspection.
    /// Production code does not call this; the default observer is `nil`.
    func setLifecycleObserver(_ observer: (@Sendable (ModelLifecycleEvent) -> Void)?) async {
        await lifecycleActor.setObserver(observer)
    }

    // MARK: - Inference coordination

    nonisolated func beginInference() async {
        await lifecycleActor.beginInference()
    }

    nonisolated func endInference() async {
        await lifecycleActor.endInference()
    }

    // MARK: - Private helpers

    private func performDownload() async {
        state = .downloading(progress: 0)

        let fm = FileManager.default
        let legacyRoot = config.modelDirectory
        let container = Self.modelContainer(forLegacyRoot: legacyRoot)
        let currentDir = container.appendingPathComponent("PaddleOCR-VL.current")
        let installingRoot = container.appendingPathComponent(".installing")
        let attemptID = UUID().uuidString
        let candidate = installingRoot.appendingPathComponent("PaddleOCR-VL.next.\(attemptID)")
        let backupURL = container.appendingPathComponent("PaddleOCR-VL.backup.\(attemptID)")

        // Task 5.2 — capture pre-attempt snapshot before mutating install artifacts.
        let priorResolved = Self.resolvedActiveModelDirectory(inContainer: container, fileManager: fm)
        let priorDownloaded = config.userDefaults.bool(forKey: DefaultsKey.downloaded)
        let priorChecksum = config.userDefaults.string(forKey: DefaultsKey.checksum)
        let priorLastVerified = config.userDefaults.double(forKey: DefaultsKey.lastVerified)
        let priorEnabled = config.userDefaults.bool(forKey: DefaultsKey.enabled)
        let hadPriorValid = priorResolved != nil

        var stagingCreated = false
        var backupCreated = false

        do {
            // Heuristic: need at least 2GB free on the home volume.
            if let free = config.availableSpaceProvider(), free < 2_147_483_648 {
                throw PaddleOCRError.storageUnavailable("Insufficient disk space")
            }

            // sha256sum format is "<hash>  <filename>" — keep only the hash token.
            let rawChecksum = try await config.downloader.fetchString(from: config.checksumURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedChecksum = rawChecksum
                .components(separatedBy: .whitespaces)
                .first(where: { !$0.isEmpty }) ?? ""
            guard !expectedChecksum.isEmpty else {
                throw PaddleOCRError.downloadFailed("Empty or invalid checksum file")
            }
            DebugLogger.shared.log("Expected checksum prefix: \(expectedChecksum.prefix(16))…", level: .info, category: .modelDownload)

            let tempFile = try await config.downloader.download(from: config.modelURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: progress)
                }
            }

            // Task 5.1 — verify archive checksum BEFORE creating any install directory.
            // Hash off the main actor: the archive is multi-GB and a synchronous
            // SHA256 here would freeze the UI (same pattern as verifyOnLaunch).
            let actualChecksum = await Task.detached(priority: .userInitiated) { [tempFile] in
                Self.sha256Static(of: tempFile) ?? ""
            }.value
            DebugLogger.shared.log("Actual checksum prefix:   \(actualChecksum.prefix(16))…", level: .info, category: .modelDownload)
            guard !actualChecksum.isEmpty, actualChecksum == expectedChecksum else {
                DebugLogger.shared.log("Checksum mismatch — expected: \(expectedChecksum.prefix(16)) actual: \(actualChecksum.prefix(16))", level: .error, category: .modelDownload)
                try? fm.removeItem(at: tempFile)
                throw PaddleOCRError.verifyFailed
            }

            // Task 5.3 / 5.4 — stage candidate at `<container>/.installing/PaddleOCR-VL.next.<uuid>`
            // and move the verified archive inside it before extraction.
            try config.installFileOps.createDirectory(at: candidate, withIntermediateDirectories: true)
            stagingCreated = true
            let stagedArchive = candidate.appendingPathComponent("model.zip")
            try config.installFileOps.moveItem(at: tempFile, to: stagedArchive)

            // Task 5.5 / 5.6 — extract only into the candidate; extractor enforces path-traversal
            // and non-zero unzip exit as failures.
            try config.extractor.extract(archive: stagedArchive, into: candidate)

            // Task 5.7 — validate using the same predicate as the resolver.
            guard Self.hasSupportedModelWeights(in: candidate, fileManager: fm) else {
                throw PaddleOCRError.verifyFailed
            }

            // Task 5.8 — promote candidate to `.current`, backing up any existing `.current` first.
            if config.installFileOps.fileExists(at: currentDir) {
                try config.installFileOps.moveItem(at: currentDir, to: backupURL)
                backupCreated = true
            }

            do {
                try config.installFileOps.moveItem(at: candidate, to: currentDir)
                stagingCreated = false
            } catch let promotionError {
                // Task 5.10 — rollback from backup; if rollback fails, debug-log and rethrow.
                if backupCreated {
                    do {
                        try config.installFileOps.moveItem(at: backupURL, to: currentDir)
                        backupCreated = false
                    } catch let rollbackError {
                        DebugLogger.shared.log(
                            "Rollback from backup failed: \(rollbackError.localizedDescription)",
                            level: .error,
                            category: .modelDownload
                        )
                    }
                }
                throw promotionError
            }

            // Task 5.9 — delete backup only after promotion succeeds.
            if backupCreated {
                try? config.installFileOps.removeItem(at: backupURL)
                backupCreated = false
            }

            // Task 5.12 — update metadata only after `.current` resolves as valid.
            config.userDefaults.set(true, forKey: DefaultsKey.downloaded)
            config.userDefaults.set(expectedChecksum, forKey: DefaultsKey.checksum)
            config.userDefaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastVerified)
            config.userDefaults.set(true, forKey: DefaultsKey.enabled)
            paddleOCREnabled = true
            state = .downloaded

            // Clean up `.installing` if it is now empty.
            removeEmptyInstallingRoot(installingRoot)

        } catch is CancellationError {
            cleanupStagingArtifacts(candidate: candidate, stagingCreated: stagingCreated, installingRoot: installingRoot)
            applyDeterministicFailure(
                hadPriorValid: hadPriorValid,
                priorChecksum: priorChecksum,
                priorDownloaded: priorDownloaded,
                priorLastVerified: priorLastVerified,
                priorEnabled: priorEnabled,
                firstInstallState: .notDownloaded
            )
        } catch let error as PaddleOCRError {
            cleanupStagingArtifacts(candidate: candidate, stagingCreated: stagingCreated, installingRoot: installingRoot)
            applyDeterministicFailure(
                hadPriorValid: hadPriorValid,
                priorChecksum: priorChecksum,
                priorDownloaded: priorDownloaded,
                priorLastVerified: priorLastVerified,
                priorEnabled: priorEnabled,
                firstInstallState: .failed(error)
            )
        } catch {
            cleanupStagingArtifacts(candidate: candidate, stagingCreated: stagingCreated, installingRoot: installingRoot)
            applyDeterministicFailure(
                hadPriorValid: hadPriorValid,
                priorChecksum: priorChecksum,
                priorDownloaded: priorDownloaded,
                priorLastVerified: priorLastVerified,
                priorEnabled: priorEnabled,
                firstInstallState: .failed(.downloadFailed(error.localizedDescription))
            )
        }
    }

    private func cleanupStagingArtifacts(candidate: URL, stagingCreated: Bool, installingRoot: URL) {
        if stagingCreated {
            try? config.installFileOps.removeItem(at: candidate)
        }
        removeEmptyInstallingRoot(installingRoot)
    }

    private func removeEmptyInstallingRoot(_ installingRoot: URL) {
        if let children = try? config.installFileOps.contentsOfDirectory(at: installingRoot),
           children.isEmpty {
            try? config.installFileOps.removeItem(at: installingRoot)
        }
    }

    // Task 5.13 — restore prior downloaded state when a valid pre-attempt model existed;
    // otherwise clear metadata, disable enabled, and transition to the requested failure state.
    private func applyDeterministicFailure(
        hadPriorValid: Bool,
        priorChecksum: String?,
        priorDownloaded: Bool,
        priorLastVerified: Double,
        priorEnabled: Bool,
        firstInstallState: ModelDownloadState
    ) {
        if hadPriorValid {
            // Prior metadata was never overwritten on the success path; just re-settle the
            // in-memory @Published mirrors so observers see the prior `.downloaded` state.
            paddleOCREnabled = priorEnabled
            state = .downloaded
        } else {
            config.userDefaults.removeObject(forKey: DefaultsKey.downloaded)
            config.userDefaults.removeObject(forKey: DefaultsKey.checksum)
            config.userDefaults.removeObject(forKey: DefaultsKey.lastVerified)
            config.userDefaults.set(false, forKey: DefaultsKey.enabled)
            paddleOCREnabled = false
            state = firstInstallState
        }
        _ = priorChecksum
        _ = priorDownloaded
        _ = priorLastVerified
    }

    private func resetDownloadState() {
        config.userDefaults.removeObject(forKey: DefaultsKey.downloaded)
        config.userDefaults.removeObject(forKey: DefaultsKey.checksum)
        config.userDefaults.removeObject(forKey: DefaultsKey.lastVerified)
        config.userDefaults.set(false, forKey: DefaultsKey.enabled)
        paddleOCREnabled = false
        state = .notDownloaded
    }

    private func sha256(of url: URL) -> String? {
        Self.sha256Static(of: url)
    }

    nonisolated static func defaultModelDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
            .appendingPathComponent("PaddleOCR-VL")
    }

    // Stable main app bundle ID used to locate its sandbox container from any process.
    // Must not use Bundle.main.bundleIdentifier here — helpers, XPC, and CLI callers
    // would resolve to their own container instead of the main app's.
    nonisolated private static let mainAppBundleID = "com.chunweiliu.MangaTranslator"

    // NSHomeDirectory() is sandbox-remapped in the main app and returns the container path,
    // causing containerRoot below to double-nest. homeDirectoryForCurrentUser always returns
    // the real user home regardless of sandbox context.
    nonisolated static func productionModelSearchRoots(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> [URL] {
        let containerRoot = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(mainAppBundleID)
            .appendingPathComponent("Data")
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
            .appendingPathComponent("PaddleOCR-VL")

        return [
            defaultModelDirectory(),
            containerRoot
        ]
    }

    nonisolated static func resolvedProductionModelDirectory(
        fileManager: FileManager = .default,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> URL? {
        // Each search root is a legacy `PaddleOCR-VL` path. Resolve at the parent
        // container so the resolver can pick `.current` first, falling back to
        // legacy root, then the single valid legacy child. Calling the legacy-
        // root–scoped `resolvedModelDirectory(in:)` here would miss sibling
        // `.current` directories created by the atomic install path.
        for legacyRoot in productionModelSearchRoots(homeDirectory: homeDirectory) {
            let container = modelContainer(forLegacyRoot: legacyRoot)
            if let resolved = resolvedActiveModelDirectory(inContainer: container, fileManager: fileManager) {
                return resolved
            }
        }
        return nil
    }

    // Resolves the active local model directory from the container that holds
    // `.current`, legacy `PaddleOCR-VL`, and `.installing`. Order:
    //   1. `<container>/PaddleOCR-VL.current`
    //   2. `<container>/PaddleOCR-VL`
    //   3. single valid child under `<container>/PaddleOCR-VL`
    // Returns nil for any ambiguous or missing state.
    nonisolated static func resolvedActiveModelDirectory(
        inContainer container: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let current = container.appendingPathComponent("PaddleOCR-VL.current")
        if hasSupportedModelWeights(in: current, fileManager: fileManager) {
            return current
        }

        let legacyRoot = container.appendingPathComponent("PaddleOCR-VL")
        return resolvedModelDirectory(in: legacyRoot, fileManager: fileManager)
    }

    // The model container is the parent of the legacy `PaddleOCR-VL` directory.
    // Install transactions, `.current`, and backups all live under this container.
    nonisolated static func modelContainer(forLegacyRoot legacyRoot: URL) -> URL {
        legacyRoot.deletingLastPathComponent()
    }

    nonisolated static func resolvedModelDirectory(
        in rootDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        if hasSupportedModelWeights(in: rootDirectory, fileManager: fileManager) {
            return rootDirectory
        }

        guard fileManager.fileExists(atPath: rootDirectory.path) else { return nil }
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [URL] = []
        for child in children {
            guard
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true
            else {
                continue
            }
            if hasSupportedModelWeights(in: child, fileManager: fileManager) {
                candidates.append(child)
            }
        }

        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    nonisolated static func hasSupportedModelWeights(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let candidates = ["weights.npz", "model.safetensors"]
        return candidates.contains { name in
            fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }

    nonisolated static func sha256Static(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try? handle.read(upToCount: 65536)
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Inference coordination conformance

extension ModelDownloadService: ModelInferenceCoordinating {}

// MARK: - Lifecycle Actor

/// Observer events emitted by `ModelLifecycleActor` for test-only
/// introspection of lifecycle coordination. Production code does not attach
/// an observer.
enum ModelLifecycleEvent: Sendable, Equatable {
    case sectionEntered(String)
    case sectionExited(String)
    case waitForInferencesBegan
    case waitForInferencesResumed
}

actor ModelLifecycleActor {
    private var activeInferenceCount = 0
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []

    private var lifecycleMutationActive = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    private var observer: (@Sendable (ModelLifecycleEvent) -> Void)?

    func setObserver(_ observer: (@Sendable (ModelLifecycleEvent) -> Void)?) {
        self.observer = observer
    }

    func beginInference() {
        activeInferenceCount += 1
    }

    func endInference() {
        activeInferenceCount = max(0, activeInferenceCount - 1)
        guard activeInferenceCount == 0 else { return }
        let waiters = inferenceWaiters
        inferenceWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForActiveInferences() async {
        guard activeInferenceCount > 0 else { return }
        observer?(.waitForInferencesBegan)
        await withCheckedContinuation { continuation in
            inferenceWaiters.append(continuation)
        }
        observer?(.waitForInferencesResumed)
    }

    func beginLifecycleMutation(section: String = "") async {
        if lifecycleMutationActive {
            // Wait for the current owner to hand the lock over via
            // `endLifecycleMutation`. The handoff keeps `lifecycleMutationActive`
            // true across resume so a fresh caller cannot jump the queue.
            await withCheckedContinuation { continuation in
                mutationWaiters.append(continuation)
            }
        } else {
            lifecycleMutationActive = true
        }
        if !section.isEmpty {
            observer?(.sectionEntered(section))
        }
    }

    func endLifecycleMutation(section: String = "") {
        if !section.isEmpty {
            observer?(.sectionExited(section))
        }
        if !mutationWaiters.isEmpty {
            let next = mutationWaiters.removeFirst()
            // Leave `lifecycleMutationActive` as true: ownership transfers
            // directly to the resumed waiter instead of going through a
            // released-then-reacquired window.
            next.resume()
        } else {
            lifecycleMutationActive = false
        }
    }
}

// MARK: - URLSessionDownloader

// Bridges URLSessionDownloadTask closure API into Swift concurrency while reporting progress.
private final class DownloadTaskBox: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}

struct URLSessionDownloader: ModelDownloading {
    func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let box = DownloadTaskBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                    box.observation?.invalidate()
                    box.observation = nil

                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continuation.resume(throwing: PaddleOCRError.downloadFailed("HTTP error"))
                        return
                    }
                    guard let tempURL = tempURL else {
                        continuation.resume(throwing: PaddleOCRError.downloadFailed("No download location"))
                        return
                    }
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".zip")
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: dest)
                        continuation.resume(returning: dest)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.observation = task.progress.observe(\.fractionCompleted, options: [.new]) { _, change in
                    if let fraction = change.newValue {
                        progressHandler(fraction)
                    }
                }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
            box.observation?.invalidate()
        }
    }

    func fetchString(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PaddleOCRError.downloadFailed("Failed to fetch checksum")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
