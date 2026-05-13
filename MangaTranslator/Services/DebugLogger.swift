import Foundation
import os

// MARK: - Log Level

enum DebugLogLevel: String, CaseIterable, Codable {
    case debug
    case info
    case warning
    case error
    case fault

    var displayName: String { rawValue.capitalized }
}

// MARK: - Log Category

enum DebugLogCategory: String, CaseIterable, Codable {
    case appLifecycle = "app.lifecycle"
    case settings
    case fileInput = "file.input"
    case ocrRouter = "ocr.router"
    case ocrManga = "ocr.manga"
    case ocrPaddle = "ocr.paddle"
    case translationOpenAI = "translation.openai"
    case translationGoogle = "translation.google"
    case translationDeepL = "translation.deepl"
    case translationCopilot = "translation.copilot"
    case cache
    case modelDownload = "model.download"
    case keychain
    case export
    case debugLog = "debug.log"

    var displayName: String { rawValue }
}

// MARK: - Log Kind

enum DebugLogKind: String, CaseIterable, Codable {
    case operational
    case content
}

// MARK: - Log Entry

struct DebugLogEntry: Identifiable, Sendable {
    let id: Int64
    let timestamp: Date
    let level: DebugLogLevel
    let category: DebugLogCategory
    let kind: DebugLogKind
    let message: String
    let metadataJSON: String
    let sessionID: String
    let sourceFileOrComponent: String
    let filePath: String?
    let exportable: Bool

    var firstLineOfMessage: String {
        message.components(separatedBy: "\n").first ?? message
    }

    var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

// MARK: - Log Filter

struct DebugLogFilter: Equatable {
    var level: DebugLogLevel?
    var category: DebugLogCategory?
    var kind: DebugLogKind?
    var sessionIDFilter: SessionFilter = .all
    var startDate: Date?
    var endDate: Date?
    var textQuery: String = ""
    var exportableOnly: Bool = false

    enum SessionFilter: Equatable {
        case all
        case session(String)
    }
}

// MARK: - Credential Redaction

/// Patterns are normalized (lowercase, no `_` or `-`). A metadata key is redacted
/// when its normalized form CONTAINS any of these patterns as a substring.
/// This catches camelCase variants (responseBody), hyphenated (access-token),
/// and compound keys (AuthorizationHeader) without false-positives from short tokens.
private let credentialKeyPatterns: Set<String> = [
    "authorization", "apikey", "secret", "password",
    "credential", "accesstoken", "bearer", "token",
    "auth", "responsebody", "rawresponse", "payload", "body"
]

private func normalizeKey(_ key: String) -> String {
    key.lowercased()
       .replacingOccurrences(of: "_", with: "")
       .replacingOccurrences(of: "-", with: "")
}

func redactMetadata(_ metadata: [String: String]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: metadata.map { key, value in
        let norm = normalizeKey(key)
        let shouldRedact = credentialKeyPatterns.contains { norm.contains($0) }
        return (key, shouldRedact ? "[REDACTED]" : value)
    })
}

// MARK: - DebugLogger Facade

final class DebugLogger: Sendable {
    static let shared = DebugLogger(store: DebugLogStore.shared)

    let sessionID: String
    private let store: DebugLogStore
    private let taskLock = NSLock()
    nonisolated(unsafe) private var lastInsertTask: Task<Void, Never>?

    init(store: DebugLogStore) {
        self.sessionID = UUID().uuidString
        self.store = store
    }

    func log(
        _ message: String,
        level: DebugLogLevel,
        category: DebugLogCategory,
        kind: DebugLogKind = .operational,
        metadata: [String: String] = [:],
        filePath: String? = nil,
        source: String = #fileID
    ) {
        let safeMetadata = redactMetadata(metadata)
        let metadataJSON = (try? JSONEncoder().encode(safeMetadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let absoluteFilePath = filePath.map { path -> String in
            (path as NSString).isAbsolutePath ? path : URL(fileURLWithPath: path).path
        }

        let entry = DebugLogEntry(
            id: 0,
            timestamp: Date(),
            level: level,
            category: category,
            kind: kind,
            message: message,
            metadataJSON: metadataJSON,
            sessionID: sessionID,
            sourceFileOrComponent: source,
            filePath: absoluteFilePath,
            exportable: true
        )

        emitToOSLogger(entry)

        taskLock.lock()
        let prev = lastInsertTask
        let s = store
        let task = Task.detached {
            await prev?.value
            await s.insert(entry)
        }
        lastInsertTask = task
        taskLock.unlock()
    }

    /// Awaits all pending store inserts enqueued by `log()`.
    func flush() async {
        let task = taskLock.withLock { lastInsertTask }
        await task?.value
    }

    /// Blocks the calling thread until pending inserts are drained or the timeout elapses.
    /// Intended for use from `applicationWillTerminate` on the main thread.
    func flushSync(timeout: TimeInterval = 2.0) {
        let sema = DispatchSemaphore(value: 0)
        Task.detached { [self] in
            await self.flush()
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + timeout)
    }

    func logContent(
        _ message: String,
        category: DebugLogCategory,
        filePath: String? = nil,
        source: String = #fileID
    ) {
        log(
            message,
            level: .debug,
            category: category,
            kind: .content,
            filePath: filePath,
            source: source
        )
    }

    /// Logs structured API diagnostics. Callers MUST use this helper instead of
    /// passing raw response bodies via `log(_:metadata:)` — response content is
    /// never an accepted parameter here, enforcing the spec rule that raw API
    /// response bodies are not persisted by default.
    func logAPIDiagnostic(
        _ message: String,
        category: DebugLogCategory,
        statusCode: Int? = nil,
        model: String? = nil,
        endpoint: String? = nil,
        source: String = #fileID
    ) {
        var metadata: [String: String] = [:]
        if let code = statusCode { metadata["status_code"] = "\(code)" }
        if let model = model { metadata["model"] = model }
        if let endpoint = endpoint { metadata["endpoint"] = sanitizeEndpoint(endpoint) }
        log(message, level: .info, category: category, metadata: metadata, source: source)
    }

    /// Strips query string, fragment, and embedded credentials from a URL or path,
    /// retaining only scheme/host/path. Falls back to truncating at `?` if parsing fails.
    private func sanitizeEndpoint(_ endpoint: String) -> String {
        var components = URLComponents(string: endpoint)
        components?.query = nil
        components?.fragment = nil
        components?.user = nil
        components?.password = nil
        return components?.string ?? endpoint.components(separatedBy: "?").first ?? endpoint
    }

    private func emitToOSLogger(_ entry: DebugLogEntry) {
        let logger = Logger(subsystem: "MangaTranslator", category: entry.category.rawValue)
        let msg = entry.message
        switch entry.level {
        case .debug: logger.debug("\(msg, privacy: .public)")
        case .info: logger.info("\(msg, privacy: .public)")
        case .warning: logger.warning("\(msg, privacy: .public)")
        case .error: logger.error("\(msg, privacy: .public)")
        case .fault: logger.fault("\(msg, privacy: .public)")
        }
    }
}
