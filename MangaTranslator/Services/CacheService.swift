import Foundation
import AppKit
import SQLite3
import CryptoKit

final class CacheService {
    private var db: OpaquePointer?
    private(set) lazy var glossaryService: GlossaryService = GlossaryService(db: db)

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
            DebugLogger.shared.log("Failed to open cache database at \(dbPath)", level: .error, category: .cache)
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
        let sql = """
        SELECT bubbles_json, text_pixel_mask_png FROM translation_cache
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
    ) {
        guard let jsonString = encodeBubbles(bubbles) else { return }

        let sql = """
        INSERT OR REPLACE INTO translation_cache
            (image_hash, source_lang, target_lang, engine, bubbles_json, text_pixel_mask_png, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
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
        if let maskData = encodeMask(textPixelMask) {
            maskData.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    sqlite3_bind_null(stmt, 6)
                    return
                }
                sqlite3_bind_blob(stmt, 6, baseAddress, Int32(maskData.count), transient)
            }
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_double(stmt, 7, Date().timeIntervalSince1970)

        sqlite3_step(stmt)
    }

    func clearAll() {
        sqlite3_exec(db, "DELETE FROM translation_cache", nil, nil, nil)
    }

    func translationCacheSize() -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT SUM(LENGTH(bubbles_json)) FROM translation_cache", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
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
        let isInverted: Bool

        init(
            x: Double,
            y: Double,
            width: Double,
            height: Double,
            originalText: String,
            translatedText: String,
            index: Int,
            isInverted: Bool
        ) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.originalText = originalText
            self.translatedText = translatedText
            self.index = index
            self.isInverted = isInverted
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
                isInverted: bubble.bubble.isInverted
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
                isInverted: item.isInverted
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
