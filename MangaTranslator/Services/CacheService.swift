import Foundation
import SQLite3
import CryptoKit

final class CacheService {
    private var db: OpaquePointer?

    init() {
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        let containerURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MangaTranslator")

        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let dbPath = containerURL.appendingPathComponent("cache.sqlite").path
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database at \(dbPath)")
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
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    static func imageHash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func lookup(
        imageHash: String, source: Language, target: Language, engine: TranslationEngine
    ) -> [TranslatedBubble]? {
        let sql = """
        SELECT bubbles_json FROM translation_cache
        WHERE image_hash = ? AND source_lang = ? AND target_lang = ? AND engine = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, imageHash, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, source.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, target.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, engine.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        guard let jsonCStr = sqlite3_column_text(stmt, 0) else { return nil }
        let jsonString = String(cString: jsonCStr)

        return decodeBubbles(from: jsonString)
    }

    func store(
        imageHash: String,
        source: Language,
        target: Language,
        engine: TranslationEngine,
        bubbles: [TranslatedBubble]
    ) {
        guard let jsonString = encodeBubbles(bubbles) else { return }

        let sql = """
        INSERT OR REPLACE INTO translation_cache
            (image_hash, source_lang, target_lang, engine, bubbles_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, imageHash, -1, transient)
        sqlite3_bind_text(stmt, 2, source.rawValue, -1, transient)
        sqlite3_bind_text(stmt, 3, target.rawValue, -1, transient)
        sqlite3_bind_text(stmt, 4, engine.rawValue, -1, transient)
        sqlite3_bind_text(stmt, 5, jsonString, -1, transient)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)

        sqlite3_step(stmt)
    }

    func addHistory(path: String, pageCount: Int?) {
        let sql = """
        INSERT OR REPLACE INTO history (file_path, page_count, last_opened)
        VALUES (?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, path, -1, transient)
        if let pageCount {
            sqlite3_bind_int(stmt, 2, Int32(pageCount))
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

        sqlite3_step(stmt)
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
                index: bubble.index
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
                index: item.index
            )
            return TranslatedBubble(
                bubble: cluster,
                translatedText: item.translatedText,
                index: item.index
            )
        }
    }
}
