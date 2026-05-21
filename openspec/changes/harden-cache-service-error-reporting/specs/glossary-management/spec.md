## ADDED Requirements

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

## MODIFIED Requirements

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
