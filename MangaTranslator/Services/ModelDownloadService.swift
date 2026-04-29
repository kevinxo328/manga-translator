import Foundation
import CryptoKit
import os

// MARK: - Downloader protocol for testability

protocol ModelDownloading: Sendable {
    func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL
    func fetchString(from url: URL) async throws -> String
}

// MARK: - Configuration

struct ModelDownloadConfiguration: Sendable {
    let modelURL: URL
    let checksumURL: URL
    let modelDirectory: URL
    let userDefaults: UserDefaults
    let downloader: any ModelDownloading

    static var `default`: ModelDownloadConfiguration {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let modelDir = appSupport
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent("Models")
            .appendingPathComponent("PaddleOCR-VL")
        return ModelDownloadConfiguration(
            modelURL: URL(string: "https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx/resolve/main/model.zip")!,
            checksumURL: URL(string: "https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx/resolve/main/model.zip.sha256")!,
            modelDirectory: modelDir,
            userDefaults: .standard,
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

// MARK: - ModelDownloadService

@MainActor
final class ModelDownloadService: ObservableObject {
    @Published private(set) var state: ModelDownloadState

    static let shared = ModelDownloadService()

    private let config: ModelDownloadConfiguration
    private let logger = Logger(subsystem: "MangaTranslator", category: "ModelDownload")
    private var currentTask: Task<Void, Never>?
    private let lifecycleActor = ModelLifecycleActor()

    init(configuration: ModelDownloadConfiguration = .default) {
        self.config = configuration
        let downloaded = configuration.userDefaults.bool(forKey: DefaultsKey.downloaded)
        self.state = downloaded ? .downloaded : .notDownloaded
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

        // Full SHA256 when evidence is stale or suspicious
        let storedChecksum = config.userDefaults.string(forKey: DefaultsKey.checksum) ?? ""
        let archivePath = config.modelDirectory.appendingPathComponent("model.zip")
        let fm = FileManager.default

        guard fm.fileExists(atPath: archivePath.path) else {
            resetDownloadState()
            return
        }

        if storedChecksum.isEmpty {
            resetDownloadState()
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

            // Fetch expected checksum
            let expectedChecksum = try await config.downloader.fetchString(from: config.checksumURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Download archive
            let tempFile = try await config.downloader.download(from: config.modelURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: progress)
                }
            }

            // Verify checksum
            guard let actualChecksum = sha256(of: tempFile), actualChecksum == expectedChecksum else {
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

            // Atomic replacement
            let finalArchive = destDir.appendingPathComponent("model.zip")
            if fm.fileExists(atPath: finalArchive.path) {
                try fm.removeItem(at: finalArchive)
            }
            try fm.moveItem(at: tempFile, to: finalArchive)
            if fm.fileExists(atPath: stagingDir.path) {
                try fm.removeItem(at: stagingDir)
            }

            // Persist state
            config.userDefaults.set(true, forKey: DefaultsKey.downloaded)
            config.userDefaults.set(expectedChecksum, forKey: DefaultsKey.checksum)
            config.userDefaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastVerified)
            config.userDefaults.set(true, forKey: DefaultsKey.enabled)

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
        state = .notDownloaded
    }

    private func sha256(of url: URL) -> String? {
        Self.sha256Static(of: url)
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

struct URLSessionDownloader: ModelDownloading {
    func download(from url: URL, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: nil)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PaddleOCRError.downloadFailed("HTTP error")
        }
        return tempURL
    }

    func fetchString(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PaddleOCRError.downloadFailed("Failed to fetch checksum")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
