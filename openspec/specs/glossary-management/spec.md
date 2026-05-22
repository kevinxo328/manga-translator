## Purpose

User-managed and LLM-assisted glossaries for consistent translation of proper nouns, character names, and recurring terms across manga pages.

## Requirements

### Requirement: Glossary persistence
The system SHALL store glossaries and their terms in the existing SQLite cache database using two tables: `glossaries` (id, name, created_at) and `glossary_terms` (id, glossary_id, source_term, target_term, auto_detected, created_at). Glossaries are language-agnostic — there is no source/target language binding; the user chooses which glossary to apply regardless of the current translation direction. The system SHALL use `CREATE TABLE IF NOT EXISTS` to remain safe on existing installs.

#### Scenario: Tables created on first launch after update
- **WHEN** the app launches and the glossary tables do not exist
- **THEN** the system creates `glossaries` and `glossary_terms` tables without affecting existing cache data

### Requirement: Create and delete glossaries
The system SHALL allow users to create named glossaries (requiring a non-empty name) and delete existing glossaries along with all their terms. The delete operation SHALL be atomic: either both the `glossaries` row and every matching `glossary_terms` row are removed, or none of them are. The delete operation SHALL be implemented as an explicit SQLite transaction (`BEGIN IMMEDIATE` → delete from `glossary_terms` where `glossary_id` matches → delete from `glossaries` where `id` matches → `COMMIT`), with `ROLLBACK` on any failure. The schema SHALL NOT be migrated to add `ON DELETE CASCADE`.

#### Scenario: User creates a new glossary
- **WHEN** user taps "New Glossary" and enters a name
- **THEN** a new glossary record is created and becomes selectable in the glossary picker

#### Scenario: User deletes a glossary successfully
- **WHEN** user selects "Delete Glossary" and confirms the alert
- **AND** every step of the delete transaction (`BEGIN IMMEDIATE`, both `DELETE`s, and `COMMIT`) returns success
- **THEN** the glossary row SHALL be removed from `glossaries`
- **THEN** every `glossary_terms` row whose `glossary_id` matches the deleted glossary SHALL be removed
- **THEN** the call SHALL return normally

#### Scenario: Delete glossary terms step fails
- **WHEN** the `DELETE FROM glossary_terms WHERE glossary_id = ?` step inside the transaction returns a non-success code
- **THEN** the transaction SHALL be rolled back
- **THEN** neither the `glossaries` row nor any `glossary_terms` rows SHALL be modified
- **THEN** the call SHALL throw an error carrying the SQLite result code and message

#### Scenario: Delete glossary row step fails
- **WHEN** the `DELETE FROM glossaries WHERE id = ?` step inside the transaction returns a non-success code
- **THEN** the transaction SHALL be rolled back
- **THEN** the previously-deleted `glossary_terms` rows SHALL be restored by `ROLLBACK`
- **THEN** the call SHALL throw an error carrying the SQLite result code and message

#### Scenario: Delete glossary while cache is unavailable
- **WHEN** the user confirms the delete alert and `CacheService.isAvailable == false`
- **THEN** the transaction SHALL NOT be opened
- **THEN** no row in either `glossaries` or `glossary_terms` SHALL be modified
- **THEN** the call SHALL throw `CacheError.unavailable`

### Requirement: Glossary mutations report failure to the caller
The system SHALL make every `GlossaryService` mutation (`createGlossary`, `deleteGlossary`, `addTerm`, `updateTerm`, `deleteTerm`, and any LLM auto-detected term insert) `throws`. A successful return SHALL mean the database has accepted the change. A thrown error SHALL carry the SQLite result code and message and SHALL NOT silently leave partial state in either `glossaries` or `glossary_terms`. Read APIs (`listGlossaries`, `listTerms`) SHALL remain non-throwing.

#### Scenario: Glossary edit succeeds
- **WHEN** `glossaryService.addTerm(glossaryID:, source:, target:)` runs against an available cache
- **AND** SQLite returns success for the underlying `INSERT`
- **THEN** the call SHALL return normally
- **THEN** the new term SHALL appear in `listTerms(glossaryID:)`

#### Scenario: Glossary edit fails
- **WHEN** a `GlossaryService` mutation call encounters a non-success SQLite result code
- **THEN** the call SHALL throw an error that carries the SQLite result code and message
- **THEN** the in-memory state of the calling view SHALL NOT be updated as if the edit succeeded

#### Scenario: Glossary edit on unavailable cache
- **WHEN** any `GlossaryService` mutation is invoked while `CacheService.isAvailable == false`
- **THEN** the call SHALL throw `CacheError.unavailable`
- **THEN** the database SHALL NOT be touched

### Requirement: Add, edit, and delete glossary terms
The system SHALL allow users to add new source→target term mappings, edit existing mappings, and delete individual terms within a glossary.

#### Scenario: User adds a term manually
- **WHEN** user taps "+ Add Term" and enters source and target text
- **THEN** the term is saved with `auto_detected = false` and appears in the glossary list

#### Scenario: User edits an existing term
- **WHEN** user selects a term and modifies source or target text
- **THEN** the updated mapping is persisted immediately

#### Scenario: User deletes a term
- **WHEN** user swipe-deletes or selects delete on a term
- **THEN** the term is removed from the database and no longer appears in the list

### Requirement: LLM auto-detection writes to glossary
The system SHALL parse `detected_terms` from LLM translation responses and insert any new source terms (not already present in the active glossary) as `auto_detected = true` entries.

#### Scenario: LLM detects a new proper noun
- **WHEN** the LLM returns `detected_terms: [{"source": "炭治郎", "target": "Tanjiro"}]` and no such source term exists in the active glossary
- **THEN** the term is inserted with `auto_detected = true`

#### Scenario: LLM detects a term already in the glossary
- **WHEN** the LLM returns a `detected_terms` entry whose source term already exists
- **THEN** the existing entry is not overwritten

### Requirement: Glossary picker in main UI
The system SHALL display a glossary selector in the main interface that shows the active glossary name (or "None"). Users SHALL be able to switch glossaries or clear the selection at any time. The selection is session-only and resets to "None" on app launch.

#### Scenario: User selects a glossary
- **WHEN** user opens the glossary picker and selects a named glossary
- **THEN** the toolbar reflects the selected name and subsequent translations use that glossary's terms

#### Scenario: User clears glossary selection
- **WHEN** user selects "None" in the glossary picker
- **THEN** subsequent translations proceed without glossary injection

### Requirement: Glossary management sheet
The system SHALL provide a modal sheet accessible from the toolbar for managing glossaries. The sheet SHALL list all glossaries, allow switching the active glossary, and provide full CRUD for both glossaries and their terms. Each term SHALL display its source text, target text, and whether it was auto-detected.

#### Scenario: Sheet shows auto-detected vs manual terms
- **WHEN** user opens the glossary management sheet
- **THEN** auto-detected terms are visually distinguished (e.g., a label or icon) from manually entered terms
