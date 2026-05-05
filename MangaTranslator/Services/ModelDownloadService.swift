import Foundation
import Combine
import CryptoKit
import os

// MARK: - Downloader protocol for testability

protocol ModelDownloading: Sendable {
    func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL
    func fetchString(from url: URL) async throws -> String
}

// MARK: - Configuration

struct ModelDownloadConfiguration {
    let modelURL: URL
    let checksumURL: URL
    let modelDirectory: URL
    let userDefaults: UserDefaults
    let downloader: any ModelDownloading

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
    private let logger = Logger(subsystem: "MangaTranslator", category: "ModelDownload")
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
        cleanupPartialFiles()
        state = .notDownloaded
    }

    func delete() async throws {
        await lifecycleActor.waitForActiveInferences()

        let fm = FileManager.default
        let dir = config.modelDirectory
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }

        config.userDefaults.removeObject(forKey: DefaultsKey.downloaded)
        config.userDefaults.removeObject(forKey: DefaultsKey.checksum)
        config.userDefaults.removeObject(forKey: DefaultsKey.lastVerified)
        config.userDefaults.set(false, forKey: DefaultsKey.enabled)
        paddleOCREnabled = false
        state = .notDownloaded
    }

    func verify() async -> Bool {
        let archivePath = config.modelDirectory.appendingPathComponent("model.zip")
        let fm = FileManager.default
        guard fm.fileExists(atPath: archivePath.path) else { return false }

        let storedChecksum = config.userDefaults.string(forKey: DefaultsKey.checksum) ?? ""
        guard !storedChecksum.isEmpty else { return false }

        guard let computed = sha256(of: archivePath) else { return false }
        return computed == storedChecksum
    }

    func verifyOnLaunch() async {
        guard config.userDefaults.bool(forKey: DefaultsKey.downloaded) else { return }

        // Fast-path when integrity evidence is fresh (within last 7 days)
        let lastVerified = config.userDefaults.double(forKey: DefaultsKey.lastVerified)
        let now = Date().timeIntervalSince1970
        let isFresh = (now - lastVerified) < (86400 * 7)

        // Full SHA256 when evidence is stale or suspicious
        let storedChecksum = config.userDefaults.string(forKey: DefaultsKey.checksum) ?? ""
        let archivePath = config.modelDirectory.appendingPathComponent("model.zip")
        let fm = FileManager.default

        guard fm.fileExists(atPath: archivePath.path) else {
            resetDownloadState()
            return
        }

        guard Self.resolvedModelDirectory(in: config.modelDirectory, fileManager: fm) != nil else {
            resetDownloadState()
            return
        }

        if storedChecksum.isEmpty {
            resetDownloadState()
            return
        }

        if isFresh {
            state = .downloaded
            return
        }

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

        do {
            // Check disk space (heuristic: need at least 2GB free)
            let fm = FileManager.default
            let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let free = attrs?[.systemFreeSize] as? Int64, free < 2_147_483_648 {
                throw PaddleOCRError.storageUnavailable("Insufficient disk space")
            }

            // Fetch expected checksum; sha256sum format is "<hash>  <filename>" — extract first token
            let rawChecksum = try await config.downloader.fetchString(from: config.checksumURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedChecksum = rawChecksum
                .components(separatedBy: .whitespaces)
                .first(where: { !$0.isEmpty }) ?? ""
            guard !expectedChecksum.isEmpty else {
                throw PaddleOCRError.downloadFailed("Empty or invalid checksum file")
            }
            logger.info("Expected checksum prefix: \(expectedChecksum.prefix(16), privacy: .public)…")

            // Download archive
            let tempFile = try await config.downloader.download(from: config.modelURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: progress)
                }
            }

            // Verify checksum
            let actualChecksum = sha256(of: tempFile) ?? ""
            logger.info("Actual checksum prefix:   \(actualChecksum.prefix(16), privacy: .public)…")
            guard !actualChecksum.isEmpty, actualChecksum == expectedChecksum else {
                logger.error("Checksum mismatch — expected: \(expectedChecksum.prefix(16), privacy: .public) actual: \(actualChecksum.prefix(16), privacy: .public)")
                try? fm.removeItem(at: tempFile)
                throw PaddleOCRError.verifyFailed
            }

            // Create destination directory
            let destDir = config.modelDirectory
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Ensure destination is writable
            guard fm.isWritableFile(atPath: destDir.path) else {
                try? fm.removeItem(at: tempFile)
                throw PaddleOCRError.storageUnavailable("Model directory is not writable")
            }

            // Extract with path traversal protection
            let stagingDir = destDir.appendingPathComponent(".staging_\(UUID().uuidString)")
            try extractZipSecurely(from: tempFile, to: stagingDir, root: destDir)

            // Move extracted files into destDir so the recognizer can load them
            if let extractedItems = try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) {
                for item in extractedItems {
                    let dest = destDir.appendingPathComponent(item.lastPathComponent)
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.moveItem(at: item, to: dest)
                }
            }
            try? fm.removeItem(at: stagingDir)

            // Keep the verified archive alongside extracted files
            let finalArchive = destDir.appendingPathComponent("model.zip")
            if fm.fileExists(atPath: finalArchive.path) {
                try fm.removeItem(at: finalArchive)
            }
            try fm.moveItem(at: tempFile, to: finalArchive)

            // Persist state
            config.userDefaults.set(true, forKey: DefaultsKey.downloaded)
            config.userDefaults.set(expectedChecksum, forKey: DefaultsKey.checksum)
            config.userDefaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastVerified)
            config.userDefaults.set(true, forKey: DefaultsKey.enabled)
            paddleOCREnabled = true

            state = .downloaded

        } catch is CancellationError {
            cleanupPartialFiles()
            state = .notDownloaded
        } catch let error as PaddleOCRError {
            state = .failed(error)
        } catch {
            state = .failed(.downloadFailed(error.localizedDescription))
        }
    }

    private func cleanupPartialFiles() {
        let fm = FileManager.default
        let dir = config.modelDirectory
        let archive = dir.appendingPathComponent("model.zip")
        try? fm.removeItem(at: archive)
    }

    private func extractZipSecurely(from archive: URL, to staging: URL, root: URL) throws {
        // Security: Process unzips to staging; reject path traversal
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", archive.path, "-d", staging.path]

        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe

        try task.run()
        task.waitUntilExit()

        // Check for path traversal: all extracted entries must be within staging
        guard let enumerator = fm.enumerator(at: staging, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            let resolved = url.standardized
            if !resolved.path.hasPrefix(staging.standardized.path) {
                try fm.removeItem(at: staging)
                throw PaddleOCRError.verifyFailed
            }
        }
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

    nonisolated static func productionModelSearchRoots(homeDirectory: String = NSHomeDirectory()) -> [URL] {
        let containerRoot = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent("com.chunweiliu.MangaTranslator")
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
        homeDirectory: String = NSHomeDirectory()
    ) -> URL? {
        for root in productionModelSearchRoots(homeDirectory: homeDirectory) {
            if let resolved = resolvedModelDirectory(in: root, fileManager: fileManager) {
                return resolved
            }
        }
        return nil
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

// MARK: - Lifecycle Actor

actor ModelLifecycleActor {
    private var activeInferenceCount = 0

    func beginInference() {
        activeInferenceCount += 1
    }

    func endInference() {
        activeInferenceCount = max(0, activeInferenceCount - 1)
    }

    func waitForActiveInferences() async {
        while activeInferenceCount > 0 {
            await Task.yield()
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
