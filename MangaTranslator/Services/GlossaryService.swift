import Foundation
import SQLite3

final class GlossaryService {
    private let db: OpaquePointer?
    private let isAvailable: Bool

    init(db: OpaquePointer?, isAvailable: Bool) {
        self.db = db
        self.isAvailable = isAvailable
    }

    private var transient: sqlite3_destructor_type {
        CacheService.sqliteTransient
    }

    // MARK: - Name normalization

    // Trims whitespace/newlines and validates the persisted display name.
    // Callers must use this before any mutation SQL interaction.
    private func normalizeGlossaryName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlossaryValidationError.emptyName }
        if trimmed.count > 20 {
            throw GlossaryValidationError.nameTooLong(max: 20)
        }
        return trimmed
    }

    private func validateUniqueGlossaryName(_ name: String, excludingID excludedID: String? = nil) throws {
        let duplicate = listGlossaries().contains { glossary in
            glossary.name == name && glossary.id != excludedID
        }
        if duplicate {
            throw GlossaryValidationError.duplicateName
        }
    }

    // MARK: - Glossary CRUD

    func createGlossary(name: String) throws -> Glossary {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let normalized = try normalizeGlossaryName(name)
        try validateUniqueGlossaryName(normalized)
        let id = UUID().uuidString
        let sql = """
        INSERT INTO glossaries (id, name, source_lang, target_lang, created_at) VALUES (?, ?, '', '', ?)
        """
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "GlossaryService.createGlossary.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_bind_text(stmt, 2, normalized, -1, transient)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "GlossaryService.createGlossary")
        }
        return Glossary(id: id, name: normalized)
    }

    func renameGlossary(id: String, newName: String) throws {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let normalized = try normalizeGlossaryName(newName)
        try validateUniqueGlossaryName(normalized, excludingID: id)
        let sql = "UPDATE glossaries SET name = ? WHERE id = ?"
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "GlossaryService.renameGlossary.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, normalized, -1, transient)
        sqlite3_bind_text(stmt, 2, id, -1, transient)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "GlossaryService.renameGlossary")
        }
    }

    func listGlossaries() -> [Glossary] {
        guard isAvailable, let db else { return [] }
        let sql = "SELECT id, name FROM glossaries ORDER BY created_at"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var glossaries: [Glossary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(stmt, 0),
                let nameC = sqlite3_column_text(stmt, 1)
            else { continue }
            glossaries.append(Glossary(id: String(cString: idC), name: String(cString: nameC)))
        }
        return glossaries
    }

    // Atomic delete: terms and glossary row removed together, or both rolled back.
    // Schema unchanged; we do not rely on ON DELETE CASCADE.
    func deleteGlossary(id: String) throws {
        guard isAvailable, let db else { throw CacheError.unavailable }

        let beginResult = sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        if beginResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "GlossaryService.deleteGlossary.begin")
        }

        do {
            try executePreparedDelete(
                db: db,
                sql: "DELETE FROM glossary_terms WHERE glossary_id = ?",
                id: id,
                operation: "GlossaryService.deleteGlossary.terms"
            )
            try executePreparedDelete(
                db: db,
                sql: "DELETE FROM glossaries WHERE id = ?",
                id: id,
                operation: "GlossaryService.deleteGlossary.glossary"
            )
            let commitResult = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            if commitResult != SQLITE_OK {
                let commitError = CacheService.makeError(db: db, operation: "GlossaryService.deleteGlossary.commit")
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw commitError
            }
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func executePreparedDelete(
        db: OpaquePointer,
        sql: String,
        id: String,
        operation: String
    ) throws {
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: operation + ".prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: operation)
        }
    }

    // MARK: - Term CRUD

    func addTerm(
        glossaryID: String,
        sourceTerm: String,
        targetTerm: String,
        autoDetected: Bool
    ) throws -> GlossaryTerm {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let id = UUID().uuidString
        let sql = """
        INSERT INTO glossary_terms (id, glossary_id, source_term, target_term, auto_detected, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "GlossaryService.addTerm.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_bind_text(stmt, 2, glossaryID, -1, transient)
        sqlite3_bind_text(stmt, 3, sourceTerm, -1, transient)
        sqlite3_bind_text(stmt, 4, targetTerm, -1, transient)
        sqlite3_bind_int(stmt, 5, autoDetected ? 1 : 0)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "GlossaryService.addTerm")
        }
        return GlossaryTerm(id: id, sourceTerm: sourceTerm, targetTerm: targetTerm, autoDetected: autoDetected)
    }

    func updateTerm(id: String, sourceTerm: String, targetTerm: String) throws {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let sql = "UPDATE glossary_terms SET source_term = ?, target_term = ? WHERE id = ?"
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "GlossaryService.updateTerm.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceTerm, -1, transient)
        sqlite3_bind_text(stmt, 2, targetTerm, -1, transient)
        sqlite3_bind_text(stmt, 3, id, -1, transient)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "GlossaryService.updateTerm")
        }
    }

    func deleteTerm(id: String) throws {
        guard isAvailable, let db else { throw CacheError.unavailable }
        let sql = "DELETE FROM glossary_terms WHERE id = ?"
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prepareResult != SQLITE_OK {
            throw CacheService.makeError(db: db, operation: "GlossaryService.deleteTerm.prepare")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, transient)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw CacheService.makeError(db: db, operation: "GlossaryService.deleteTerm")
        }
    }

    func listTerms(glossaryID: String) -> [GlossaryTerm] {
        guard isAvailable, let db else { return [] }
        let sql = """
        SELECT id, source_term, target_term, auto_detected
        FROM glossary_terms WHERE glossary_id = ? ORDER BY created_at DESC
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

    func insertDetectedTerms(_ terms: [GlossaryTerm], glossaryID: String) throws {
        guard isAvailable else { throw CacheError.unavailable }
        let existing = listTerms(glossaryID: glossaryID)
        let existingSources = Set(existing.map { $0.sourceTerm })
        for term in terms where !existingSources.contains(term.sourceTerm) {
            _ = try addTerm(
                glossaryID: glossaryID,
                sourceTerm: term.sourceTerm,
                targetTerm: term.targetTerm,
                autoDetected: true
            )
        }
    }
}
