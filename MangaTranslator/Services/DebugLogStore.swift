import Foundation
import SQLite3
import os

private let storeLogger = Logger(subsystem: "MangaTranslator", category: "debug.log")

// MARK: - DebugLogStore

actor DebugLogStore {
    static let shared = DebugLogStore()

    private var db: OpaquePointer?
    private(set) var isAvailable = false
    private var insertsSinceRotation = 0
    private var initialRotationTask: Task<Void, Never>?

    static let retentionDays = 14
    static let retentionMaxCount = 10_000
    static let rotationInsertInterval = 100
    static let pageSize = 100
    static let uiCap = 500

    init(databaseURL: URL? = nil) {
        let url = databaseURL ?? Self.defaultDatabaseURL()

        var ptr: OpaquePointer?
        guard sqlite3_open(url.path, &ptr) == SQLITE_OK else {
            storeLogger.error("Failed to open debug log database at \(url.path, privacy: .public)")
            return
        }
        db = ptr
        isAvailable = true

        guard Self.applySchema(db: ptr) else {
            sqlite3_close(ptr)
            db = nil
            isAvailable = false
            storeLogger.error("Failed to initialize debug log schema")
            return
        }

        initialRotationTask = Task { await runRotation() }
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Launch readiness

    /// Awaits the initial launch rotation. Fast no-op once rotation has completed.
    func awaitInitialRotation() async {
        await initialRotationTask?.value
    }

    // MARK: - Insert

    func insert(_ entry: DebugLogEntry) async {
        guard isAvailable else { return }
        let sql = """
        INSERT INTO debug_log_entries
            (timestamp, level, category, kind, message, metadata_json,
             session_id, source_file_or_component, file_path, exportable)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let tr = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_double(stmt, 1, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, entry.level.rawValue, -1, tr)
        sqlite3_bind_text(stmt, 3, entry.category.rawValue, -1, tr)
        sqlite3_bind_text(stmt, 4, entry.kind.rawValue, -1, tr)
        sqlite3_bind_text(stmt, 5, entry.message, -1, tr)
        sqlite3_bind_text(stmt, 6, entry.metadataJSON, -1, tr)
        sqlite3_bind_text(stmt, 7, entry.sessionID, -1, tr)
        sqlite3_bind_text(stmt, 8, entry.sourceFileOrComponent, -1, tr)
        if let fp = entry.filePath {
            sqlite3_bind_text(stmt, 9, fp, -1, tr)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        sqlite3_bind_int(stmt, 10, entry.exportable ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            storeLogger.error("Failed to insert debug log entry")
            return
        }

        insertsSinceRotation += 1
        if insertsSinceRotation >= Self.rotationInsertInterval {
            insertsSinceRotation = 0
            await runRotation()
        }
    }

    // MARK: - Query

    func query(filter: DebugLogFilter, offset: Int = 0) async -> [DebugLogEntry] {
        guard isAvailable else { return [] }
        let (whereClause, bindings) = buildWhereClause(filter: filter)
        let sql = """
        SELECT id, timestamp, level, category, kind, message, metadata_json,
               session_id, source_file_or_component, file_path, exportable
        FROM debug_log_entries
        \(whereClause)
        ORDER BY timestamp DESC, id DESC
        LIMIT \(Self.pageSize) OFFSET \(offset)
        """
        return executeQuery(sql: sql, bindings: bindings)
    }

    func queryAll(filter: DebugLogFilter) async -> [DebugLogEntry] {
        guard isAvailable else { return [] }
        let (whereClause, bindings) = buildWhereClause(filter: filter)
        let sql = """
        SELECT id, timestamp, level, category, kind, message, metadata_json,
               session_id, source_file_or_component, file_path, exportable
        FROM debug_log_entries
        \(whereClause)
        ORDER BY timestamp DESC, id DESC
        """
        return executeQuery(sql: sql, bindings: bindings)
    }

    func count(filter: DebugLogFilter) async -> Int {
        guard isAvailable else { return 0 }
        let (whereClause, bindings) = buildWhereClause(filter: filter)
        let sql = "SELECT COUNT(*) FROM debug_log_entries \(whereClause)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt: stmt, bindings: bindings)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Delete

    func delete(filter: DebugLogFilter) async {
        guard isAvailable else { return }
        let (whereClause, bindings) = buildWhereClause(filter: filter)
        let isEmpty = filter == DebugLogFilter()
        let sql = isEmpty
            ? "DELETE FROM debug_log_entries"
            : "DELETE FROM debug_log_entries \(whereClause)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        if !isEmpty { bindValues(stmt: stmt, bindings: bindings) }
        sqlite3_step(stmt)
    }

    func deleteAll() async {
        guard isAvailable else { return }
        sqlite3_exec(db, "DELETE FROM debug_log_entries", nil, nil, nil)
    }

    // MARK: - Export (NDJSON)

    func exportNDJSON(filter: DebugLogFilter) async -> String {
        var exportFilter = filter
        exportFilter.exportableOnly = true
        let entries = await queryAll(filter: exportFilter)
        return entries.map { entry in
            let obj: [String: Any?] = [
                "id": entry.id,
                "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                "level": entry.level.rawValue,
                "category": entry.category.rawValue,
                "kind": entry.kind.rawValue,
                "message": entry.message,
                "metadata": entry.metadataJSON,
                "session_id": entry.sessionID,
                "source": entry.sourceFileOrComponent,
                "file_path": entry.filePath
            ]
            let compacted: [String: Any] = obj.compactMapValues { $0 }
            let data = (try? JSONSerialization.data(withJSONObject: compacted)) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }.joined(separator: "\n")
    }

    // MARK: - Rotation

    func runRotation() async {
        guard isAvailable else { return }
        deleteByAge()
        deleteByCount()
    }

    // MARK: - Private helpers

    private func deleteByAge() {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86400)
        let sql = "DELETE FROM debug_log_entries WHERE timestamp < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    private func deleteByCount() {
        let sql = """
        DELETE FROM debug_log_entries
        WHERE id NOT IN (
            SELECT id FROM debug_log_entries
            ORDER BY timestamp DESC, id DESC
            LIMIT \(Self.retentionMaxCount)
        )
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static func defaultDatabaseURL() -> URL {
        let container = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MangaTranslator")
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent("debug_logs.sqlite")
    }

    private static func applySchema(db: OpaquePointer?) -> Bool {
        let versionSQL = "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)"
        guard sqlite3_exec(db, versionSQL, nil, nil, nil) == SQLITE_OK else { return false }

        var currentVersion: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT version FROM schema_version LIMIT 1", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                currentVersion = sqlite3_column_int(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)

        if currentVersion < 1 {
            let tableSQL = """
            CREATE TABLE IF NOT EXISTS debug_log_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                level TEXT NOT NULL,
                category TEXT NOT NULL,
                kind TEXT NOT NULL DEFAULT 'operational',
                message TEXT NOT NULL,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                session_id TEXT NOT NULL,
                source_file_or_component TEXT NOT NULL DEFAULT '',
                file_path TEXT,
                exportable INTEGER NOT NULL DEFAULT 1
            );
            CREATE INDEX IF NOT EXISTS idx_debug_log_ts ON debug_log_entries(timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_debug_log_level ON debug_log_entries(level);
            CREATE INDEX IF NOT EXISTS idx_debug_log_category ON debug_log_entries(category);
            CREATE INDEX IF NOT EXISTS idx_debug_log_session ON debug_log_entries(session_id);
            CREATE INDEX IF NOT EXISTS idx_debug_log_kind ON debug_log_entries(kind);
            DELETE FROM schema_version;
            INSERT INTO schema_version VALUES (1);
            """
            guard sqlite3_exec(db, tableSQL, nil, nil, nil) == SQLITE_OK else { return false }
        }
        return true
    }

    private func buildWhereClause(filter: DebugLogFilter) -> (String, [Any]) {
        var conditions: [String] = []
        var bindings: [Any] = []

        if let level = filter.level {
            conditions.append("level = ?")
            bindings.append(level.rawValue)
        }
        if let category = filter.category {
            conditions.append("category = ?")
            bindings.append(category.rawValue)
        }
        if let kind = filter.kind {
            conditions.append("kind = ?")
            bindings.append(kind.rawValue)
        }
        if case .session(let sid) = filter.sessionIDFilter {
            conditions.append("session_id = ?")
            bindings.append(sid)
        }
        if let start = filter.startDate {
            conditions.append("timestamp >= ?")
            bindings.append(start.timeIntervalSince1970)
        }
        if let end = filter.endDate {
            conditions.append("timestamp <= ?")
            bindings.append(end.timeIntervalSince1970)
        }
        if !filter.textQuery.isEmpty {
            let q = "%\(filter.textQuery)%"
            conditions.append("""
            (message LIKE ? OR category LIKE ? OR metadata_json LIKE ? OR
             COALESCE(file_path, '') LIKE ?)
            """)
            bindings.append(contentsOf: [q, q, q, q])
        }
        if filter.exportableOnly {
            conditions.append("exportable = 1")
        }

        let clause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return (clause, bindings)
    }

    private func executeQuery(sql: String, bindings: [Any]) -> [DebugLogEntry] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt: stmt, bindings: bindings)

        var results: [DebugLogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = rowToEntry(stmt: stmt) {
                results.append(entry)
            }
        }
        return results
    }

    private func bindValues(stmt: OpaquePointer?, bindings: [Any]) {
        for (i, binding) in bindings.enumerated() {
            let col = Int32(i + 1)
            let tr = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            if let s = binding as? String {
                sqlite3_bind_text(stmt, col, s, -1, tr)
            } else if let d = binding as? Double {
                sqlite3_bind_double(stmt, col, d)
            } else if let n = binding as? Int {
                sqlite3_bind_int64(stmt, col, Int64(n))
            }
        }
    }

    private func rowToEntry(stmt: OpaquePointer?) -> DebugLogEntry? {
        let id = sqlite3_column_int64(stmt, 0)
        let ts = sqlite3_column_double(stmt, 1)
        guard
            let levelStr = sqlite3_column_text(stmt, 2).map(String.init(cString:)),
            let categoryStr = sqlite3_column_text(stmt, 3).map(String.init(cString:)),
            let kindStr = sqlite3_column_text(stmt, 4).map(String.init(cString:)),
            let message = sqlite3_column_text(stmt, 5).map(String.init(cString:)),
            let metaJSON = sqlite3_column_text(stmt, 6).map(String.init(cString:)),
            let sessionID = sqlite3_column_text(stmt, 7).map(String.init(cString:)),
            let source = sqlite3_column_text(stmt, 8).map(String.init(cString:)),
            let level = DebugLogLevel(rawValue: levelStr),
            let category = DebugLogCategory(rawValue: categoryStr),
            let kind = DebugLogKind(rawValue: kindStr)
        else { return nil }

        let filePath = sqlite3_column_text(stmt, 9).map(String.init(cString:))
        let exportable = sqlite3_column_int(stmt, 10) != 0

        return DebugLogEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: ts),
            level: level,
            category: category,
            kind: kind,
            message: message,
            metadataJSON: metaJSON,
            sessionID: sessionID,
            sourceFileOrComponent: source,
            filePath: filePath,
            exportable: exportable
        )
    }
}
