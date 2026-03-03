import Foundation
import SQLite3

final class GlossaryService {
    private let db: OpaquePointer?

    init(db: OpaquePointer?) {
        self.db = db
    }

    private var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    // MARK: - Glossary CRUD

    func createGlossary(name: String, sourceLang: Language, targetLang: Language) -> Glossary? {
        let id = UUID().uuidString
        let sql = """
        INSERT INTO glossaries (id, name, source_lang, target_lang, created_at) VALUES (?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_bind_text(stmt, 2, name, -1, transient)
        sqlite3_bind_text(stmt, 3, sourceLang.rawValue, -1, transient)
        sqlite3_bind_text(stmt, 4, targetLang.rawValue, -1, transient)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return Glossary(id: id, name: name, sourceLang: sourceLang, targetLang: targetLang)
    }

    func listGlossaries() -> [Glossary] {
        let sql = "SELECT id, name, source_lang, target_lang FROM glossaries ORDER BY created_at"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var glossaries: [Glossary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(stmt, 0),
                let nameC = sqlite3_column_text(stmt, 1),
                let srcC = sqlite3_column_text(stmt, 2),
                let tgtC = sqlite3_column_text(stmt, 3)
            else { continue }

            let id = String(cString: idC)
            let name = String(cString: nameC)
            let srcRaw = String(cString: srcC)
            let tgtRaw = String(cString: tgtC)

            guard let src = Language(rawValue: srcRaw), let tgt = Language(rawValue: tgtRaw) else { continue }
            glossaries.append(Glossary(id: id, name: name, sourceLang: src, targetLang: tgt))
        }
        return glossaries
    }

    func deleteGlossary(id: String) {
        sqlite3_exec(db, "DELETE FROM glossary_terms WHERE glossary_id = '\(id)'", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM glossaries WHERE id = '\(id)'", nil, nil, nil)
    }

    // MARK: - Term CRUD

    func insertTerm(glossaryID: String, sourceTerm: String, targetTerm: String, autoDetected: Bool) -> GlossaryTerm? {
        let id = UUID().uuidString
        let sql = """
        INSERT INTO glossary_terms (id, glossary_id, source_term, target_term, auto_detected, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_bind_text(stmt, 2, glossaryID, -1, transient)
        sqlite3_bind_text(stmt, 3, sourceTerm, -1, transient)
        sqlite3_bind_text(stmt, 4, targetTerm, -1, transient)
        sqlite3_bind_int(stmt, 5, autoDetected ? 1 : 0)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return GlossaryTerm(id: id, sourceTerm: sourceTerm, targetTerm: targetTerm, autoDetected: autoDetected)
    }

    func updateTerm(id: String, sourceTerm: String, targetTerm: String) {
        let sql = "UPDATE glossary_terms SET source_term = ?, target_term = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceTerm, -1, transient)
        sqlite3_bind_text(stmt, 2, targetTerm, -1, transient)
        sqlite3_bind_text(stmt, 3, id, -1, transient)
        sqlite3_step(stmt)
    }

    func deleteTerm(id: String) {
        let sql = "DELETE FROM glossary_terms WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_step(stmt)
    }

    func listTerms(glossaryID: String) -> [GlossaryTerm] {
        let sql = """
        SELECT id, source_term, target_term, auto_detected
        FROM glossary_terms WHERE glossary_id = ? ORDER BY created_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, glossaryID, -1, transient)

        var terms: [GlossaryTerm] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(stmt, 0),
                let srcC = sqlite3_column_text(stmt, 1),
                let tgtC = sqlite3_column_text(stmt, 2)
            else { continue }
            let auto = sqlite3_column_int(stmt, 3) != 0
            terms.append(GlossaryTerm(
                id: String(cString: idC),
                sourceTerm: String(cString: srcC),
                targetTerm: String(cString: tgtC),
                autoDetected: auto
            ))
        }
        return terms
    }

    // MARK: - Auto-detection: insert only if source term doesn't already exist

    func insertDetectedTerms(_ terms: [GlossaryTerm], glossaryID: String) {
        let existing = listTerms(glossaryID: glossaryID)
        let existingSources = Set(existing.map { $0.sourceTerm })
        for term in terms where !existingSources.contains(term.sourceTerm) {
            _ = insertTerm(
                glossaryID: glossaryID,
                sourceTerm: term.sourceTerm,
                targetTerm: term.targetTerm,
                autoDetected: true
            )
        }
    }
}
