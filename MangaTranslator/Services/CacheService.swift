import Foundation
import AppKit
import SQLite3
import CryptoKit

// Errors thrown by CacheService and GlossaryService when the underlying SQLite
// database is unusable or rejects a mutation. UI surfaces only generic strings;
// the structured payload is for DebugLogger consumption.
enum CacheError: Error, Equatable {
    case unavailable
    case sqlite(code: Int32, message: String, operation: String)
}

// Validation errors thrown before any SQL is executed. These identify invalid
// caller input and are distinct from database-level failures.
enum GlossaryValidationError: Error, Equatable {
    case emptyName
    case nameTooLong(max: Int)
    case duplicateName
}

// Abstraction injected into TranslationViewModel so tests can substitute a
// double whose mutations throw. Production always uses CacheService.
protocol CacheServiceProtocol: AnyObject {
    var isAvailable: Bool { get }
    var glossaryService: GlossaryService { get }

    func lookup(
        imageHash: String, source: Language, target: Language, engine: TranslationEngine
    ) -> CacheService.CachedTranslationResult?

    func translationCacheSize() -> Int64

    func store(
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine,
        bubbles: [TranslatedBubble],
        textPixelMask: CGImage?
    ) throws

    func addHistory(path: String, pageCount: Int?) throws

    func clearAll() throws
}

final class CacheService: CacheServiceProtocol {
    private var db: OpaquePointer?
    let isAvailable: Bool
    private(set) lazy var glossaryService: GlossaryService = GlossaryService(
        db: db,
        isAvailable: isAvailable
    )

    convenience init() {
        self.init(databasePath: nil, pragmaResultOverride: nil)
    }

    // Test-friendly initializer. `databasePath == nil` uses the production
    // Application Support path. `pragmaResultOverride` lets tests force the
    // `PRAGMA foreign_keys = ON` result code, which is the only way to
    // reproduce the PRAGMA-failure branch deterministically.
    init(databasePath: String?, pragmaResultOverride: Int32? = nil) {
        let resolvedPath: String
        if let databasePath {
            resolvedPath = databasePath
        } else {
            let containerURL = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent("MangaTranslator")
            try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            resolvedPath = containerURL.appendingPathComponent("cache.sqlite").path
        }

        var handle: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let openResult = sqlite3_open_v2(resolvedPath, &handle, openFlags, nil)
        if openResult != SQLITE_OK {
            if handle != nil {
                sqlite3_close(handle)
            }
            self.db = nil
            self.isAvailable = false
            DebugLogger.shared.log(
                "Failed to open cache database (code \(openResult)) at \(resolvedPath)",
                level: .error,
                category: .cache
            )
            return
        }

        let pragmaResult = pragmaResultOverride
            ?? sqlite3_exec(handle, "PRAGMA foreign_keys = ON", nil, nil, nil)
        if pragmaResult != SQLITE_OK {
            sqlite3_close(handle)
            self.db = nil
            self.isAvailable = false
            DebugLogger.shared.log(
                "PRAGMA foreign_keys = ON failed (code \(pragmaResult)); closing handle",
                level: .error,
                category: .cache
            )
            return
        }

        self.db = handle
        self.isAvailable = true
        createTables()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS translation_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            image_hash TEXT NOT NULL,
            source_lang TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            engine TEXT NOT NULL,
            bubbles_json TEXT NOT NULL,
            text_pixel_mask_png BLOB,
            created_at REAL NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_cache_lookup
            ON translation_cache(image_hash, source_lang, target_lang, engine);

        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            page_count INTEGER,
            last_opened REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS glossaries (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            source_lang TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS glossary_terms (
            id TEXT PRIMARY KEY,
            glossary_id TEXT NOT NULL,
            source_term TEXT NOT NULL,
            target_term TEXT NOT NULL,
            auto_detected INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            FOREIGN KEY (glossary_id) REFERENCES glossaries(id)
        );
        CREATE INDEX IF NOT EXISTS idx_terms_glossary
            ON glossary_terms(glossary_id);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        ensureTranslationCacheColumns()
    }

    static func imageHash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    struct CachedTranslationResult {
        let bubbles: [TranslatedBubble]
        let textPixelMask: CGImage?
    }

    func lookup(
        imageHash: String, source: Language, target: Language, engine: TranslationEngine
    ) -> CachedTranslationResult? {
        guard isAvailable, let db else { return nil }
        let sql = """
        SELECT bubbles_json, text_pixel_mask_png FROM translation_cache
        WHERE image_hash = ? AND source_lang = ? AND target_lang = ? AND engine = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, imageHash, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 2, source.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 3, target.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 4, engine.rawValue, -1, CacheService.sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        guard let jsonCStr = sqlite3_column_text(stmt, 0) else { return nil }
        let jsonString = String(cString: jsonCStr)
        let bubbles = decodeBubbles(from: jsonString)
        let maskData: Data?
        if let blob = sqlite3_column_blob(stmt, 1) {
            let length = Int(sqlite3_column_bytes(stmt, 1))
            maskData = Data(bytes: blob, count: length)
        } else {
            maskData = nil
        }

        guard let bubbles else { return nil }
        return CachedTranslationResult(
            bubbles: bubbles,
            textPixelMask: decodeMask(from: maskData)
        )
    }

    func store(
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine,
        bubbles: [TranslatedBubble],
        textPixelMask: CGImage?
    ) throws {
        guard isAvailable, let db else { throw CacheError.unavailable }
        guard let jsonString = encodeBubbles(bubbles) else {
            throw CacheError.sqlite(code: SQLITE_ERROR, message: "Failed to encode bubbles to JSON", operation: "CacheService.store")
        }

        let sql = """
        INSERT OR REPLACE INTO translation_cache
            (image_hash, source_lang, target_lang, engine, bubbles_json, text_pixel_mask_png, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "CacheService.store.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, imageHash, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 2, source.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 3, target.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 4, engine.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 5, jsonString, -1, CacheService.sqliteTransient)
        if let maskData = encodeMask(textPixelMask) {
            maskData.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    sqlite3_bind_null(stmt, 6)
                    return
                }
                sqlite3_bind_blob(stmt, 6, baseAddress, Int32(maskData.count), CacheService.sqliteTransient)
            }
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_double(stmt, 7, Date().timeIntervalSince1970)

        let stepResult = sqlite3_step(stmt)
        if stepResult != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "CacheService.store")
        }
    }

    func clearAll() throws {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let result = sqlite3_exec(db, "DELETE FROM translation_cache", nil, nil, nil)
        if result != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "CacheService.clearAll")
        }
    }

    func translationCacheSize() -> Int64 {
        guard isAvailable, let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT SUM(LENGTH(bubbles_json)) FROM translation_cache", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }

    func addHistory(path: String, pageCount: Int?) throws {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let sql = """
        INSERT OR REPLACE INTO history (file_path, page_count, last_opened)
        VALUES (?, ?, ?)
        """

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "CacheService.addHistory.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, CacheService.sqliteTransient)
        if let pageCount {
            sqlite3_bind_int(stmt, 2, Int32(pageCount))
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

        let stepResult = sqlite3_step(stmt)
        if stepResult != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "CacheService.addHistory")
        }
    }

    // MARK: - SQLite error helpers

    // Reused SQLITE_TRANSIENT marker pointer. SQLite's headers do not expose it
    // as a Swift constant, so we synthesise it via unsafeBitCast(-1, ...).
    static let sqliteTransient: sqlite3_destructor_type = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    static func makeError(db: OpaquePointer, operation: String) -> CacheError {
        let code = sqlite3_errcode(db)
        let message: String
        if let cMessage = sqlite3_errmsg(db) {
            message = String(cString: cMessage)
        } else {
            message = "Unknown SQLite error"
        }
        return .sqlite(code: code, message: message, operation: operation)
    }

    // MARK: - Test introspection

    // Test-only helper to verify PRAGMA foreign_keys is enabled on the live
    // connection. Returns nil when the cache is unavailable.
    func _foreignKeysSetting() -> Int? {
        guard isAvailable, let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA foreign_keys", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // Test-only helper to execute arbitrary SQL on the live connection.
    // Used by tests to install triggers that force mutation failures.
    func _executeSQL(_ sql: String) -> Int32 {
        guard isAvailable, let db else { return SQLITE_MISUSE }
        return sqlite3_exec(db, sql, nil, nil, nil)
    }

    // Test-only helper that returns the raw `bubbles_json` string stored for
    // a cache key. Used by isManual round-trip tests to verify on-disk JSON
    // shape — both that the `isManual` key is always emitted on encode, and
    // that the decoder accepts JSON written without it.
    func _rawBubblesJSON(
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine
    ) -> String? {
        guard isAvailable, let db else { return nil }
        let sql = """
        SELECT bubbles_json FROM translation_cache
        WHERE image_hash = ? AND source_lang = ? AND target_lang = ? AND engine = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, imageHash, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 2, source.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 3, target.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 4, engine.rawValue, -1, CacheService.sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    // Test-only helper that overwrites the `bubbles_json` column of an
    // existing cache row. Used by tests to install legacy JSON (no `isManual`
    // key) and verify decoder backward compatibility.
    func _writeBubblesJSON(
        _ json: String,
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine
    ) -> Int32 {
        guard isAvailable, let db else { return SQLITE_MISUSE }
        let sql = """
        UPDATE translation_cache SET bubbles_json = ?
        WHERE image_hash = ? AND source_lang = ? AND target_lang = ? AND engine = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return SQLITE_ERROR }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, json, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 2, imageHash, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 3, source.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 4, target.rawValue, -1, CacheService.sqliteTransient)
        sqlite3_bind_text(stmt, 5, engine.rawValue, -1, CacheService.sqliteTransient)
        return sqlite3_step(stmt) == SQLITE_DONE ? SQLITE_OK : SQLITE_ERROR
    }

    // MARK: - JSON encoding/decoding for cached bubbles

    private struct CachedBubble: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let originalText: String
        let translatedText: String
        let index: Int
        let isInverted: Bool
        // Persists the Edit-Mode "this bubble was authored / touched by the
        // user" flag across sessions. Encoded for every entry; decoded with
        // a `false` default so cache rows written before the
        // manual-bubble-editing change still load without error.
        let isManual: Bool

        init(
            x: Double,
            y: Double,
            width: Double,
            height: Double,
            originalText: String,
            translatedText: String,
            index: Int,
            isInverted: Bool,
            isManual: Bool
        ) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.originalText = originalText
            self.translatedText = translatedText
            self.index = index
            self.isInverted = isInverted
            self.isManual = isManual
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            x = try container.decode(Double.self, forKey: .x)
            y = try container.decode(Double.self, forKey: .y)
            width = try container.decode(Double.self, forKey: .width)
            height = try container.decode(Double.self, forKey: .height)
            originalText = try container.decode(String.self, forKey: .originalText)
            translatedText = try container.decode(String.self, forKey: .translatedText)
            index = try container.decode(Int.self, forKey: .index)
            isInverted = try container.decodeIfPresent(Bool.self, forKey: .isInverted) ?? false
            isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
        }
    }

    private func encodeBubbles(_ bubbles: [TranslatedBubble]) -> String? {
        let cached = bubbles.map { bubble in
            CachedBubble(
                x: bubble.bubble.boundingBox.origin.x,
                y: bubble.bubble.boundingBox.origin.y,
                width: bubble.bubble.boundingBox.width,
                height: bubble.bubble.boundingBox.height,
                originalText: bubble.bubble.text,
                translatedText: bubble.translatedText,
                index: bubble.index,
                isInverted: bubble.bubble.isInverted,
                isManual: bubble.bubble.isManual
            )
        }

        guard let data = try? JSONEncoder().encode(cached),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private func decodeBubbles(from jsonString: String) -> [TranslatedBubble]? {
        guard let data = jsonString.data(using: .utf8),
              let cached = try? JSONDecoder().decode([CachedBubble].self, from: data) else { return nil }

        return cached.map { item in
            let rect = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            let cluster = BubbleCluster(
                boundingBox: rect,
                text: item.originalText,
                observations: [],
                index: item.index,
                isInverted: item.isInverted,
                isManual: item.isManual
            )
            return TranslatedBubble(
                bubble: cluster,
                translatedText: item.translatedText,
                index: item.index
            )
        }
    }

    private func encodeMask(_ image: CGImage?) -> Data? {
        guard let image else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private func decodeMask(from data: Data?) -> CGImage? {
        guard let data,
              let imageRep = NSBitmapImageRep(data: data) else { return nil }
        return imageRep.cgImage
    }

    private func ensureTranslationCacheColumns() {
        let sql = "PRAGMA table_info(translation_cache)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var hasMaskColumn = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let nameCStr = sqlite3_column_text(stmt, 1),
               String(cString: nameCStr) == "text_pixel_mask_png" {
                hasMaskColumn = true
                break
            }
        }

        if !hasMaskColumn {
            sqlite3_exec(db, "ALTER TABLE translation_cache ADD COLUMN text_pixel_mask_png BLOB", nil, nil, nil)
        }
    }
}
