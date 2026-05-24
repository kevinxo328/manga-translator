## Purpose

User-managed and LLM-assisted glossaries for consistent translation of proper nouns, character names, and recurring terms across manga pages.

## Requirements

### Requirement: Glossary persistence
The system SHALL store glossaries and their terms in the existing SQLite cache database using two tables: `glossaries` (id, name, created_at) and `glossary_terms` (id, glossary_id, source_term, target_term, auto_detected, created_at). Glossaries are language-agnostic — there is no source/target language binding; the user chooses which glossary to apply regardless of the current translation direction. The system SHALL use `CREATE TABLE IF NOT EXISTS` to remain safe on existing installs.

#### Scenario: Tables created on first launch after update
- **WHEN** the app launches and the glossary tables do not exist
- **THEN** the system creates `glossaries` and `glossary_terms` tables without affecting existing cache data

### Requirement: Create, rename, and delete glossaries
The system SHALL allow users to create named glossaries, rename existing glossaries, and delete existing glossaries along with all their terms. Glossary names SHALL be normalized before create or rename persistence: leading and trailing whitespace/newlines are trimmed, empty or whitespace-only names are rejected with a structured `GlossaryValidationError.emptyName` before SQL is executed, and names longer than 20 Swift `Character` values are truncated to the first 20 characters before SQL is executed. The delete operation SHALL be atomic: either both the `glossaries` row and every matching `glossary_terms` row are removed, or none of them are. The delete operation SHALL be implemented as an explicit SQLite transaction (`BEGIN IMMEDIATE` → delete from `glossary_terms` where `glossary_id` matches → delete from `glossaries` where `id` matches → `COMMIT`), with `ROLLBACK` on any failure. The schema SHALL NOT be migrated to add `ON DELETE CASCADE`.

#### Scenario: User creates a new glossary
- **WHEN** user taps "New Glossary" and enters a name
- **THEN** the name is normalized (trimmed, validated non-empty, truncated to 20 characters)
- **AND** a new glossary record is created and becomes selectable in the glossary picker

#### Scenario: User creates a glossary with an empty name
- **WHEN** user submits an empty or whitespace-only glossary name
- **THEN** the system throws `GlossaryValidationError.emptyName` before executing SQL
- **AND** no glossary record is created

#### Scenario: User renames a glossary successfully
- **WHEN** user enters a new valid name (non-empty, up to 20 characters) and confirms the rename
- **THEN** the name is normalized according to the glossary-name rules
- **AND** the glossary's name is updated in the database
- **AND** all UI pickers and references instantly reflect the updated name

#### Scenario: User renames a glossary to an empty name
- **WHEN** user clears the name or enters only whitespace and confirms
- **THEN** the system throws `GlossaryValidationError.emptyName` before executing SQL
- **AND** the existing glossary name remains unchanged

#### Scenario: User renames a glossary with name exceeding 20 characters
- **WHEN** user inputs a name longer than 20 characters
- **THEN** the system truncates the input at 20 Swift `Character` values before saving
- **AND** the persisted glossary name contains exactly the first 20 characters of the trimmed input

#### Scenario: User deletes a glossary successfully
- **WHEN** user selects the delete action and confirms the alert
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
The system SHALL make every `GlossaryService` mutation (`createGlossary`, `renameGlossary`, `deleteGlossary`, `addTerm`, `updateTerm`, `deleteTerm`, and any LLM auto-detected term insert) `throws`. A successful return SHALL mean the database has accepted the change. A thrown `GlossaryValidationError` SHALL identify invalid caller input and SHALL occur before SQL is executed. A thrown `CacheError.sqlite` SHALL carry the SQLite result code and message and SHALL NOT silently leave partial state in either `glossaries` or `glossary_terms`. Read APIs (`listGlossaries`, `listTerms`) SHALL remain non-throwing.

#### Scenario: Rename validation fails before SQL
- **WHEN** `glossaryService.renameGlossary(id:newName:)` is invoked with an empty or whitespace-only name
- **THEN** the call SHALL throw `GlossaryValidationError.emptyName`
- **AND** no SQL statement SHALL be prepared or executed
- **AND** the existing glossary name SHALL remain unchanged

#### Scenario: Glossary edit succeeds
- **WHEN** `glossaryService.addTerm(glossaryID:sourceTerm:targetTerm:autoDetected:)` runs against an available cache
- **AND** SQLite returns success for the underlying `INSERT`
- **THEN** the call SHALL return normally
- **THEN** the new term SHALL appear in `listTerms(glossaryID:)`

#### Scenario: Glossary edit fails
- **WHEN** a `GlossaryService` mutation call encounters a non-success SQLite result code
- **THEN** the call SHALL throw a `CacheError.sqlite` that carries the SQLite result code and message
- **THEN** the in-memory state of the calling view SHALL NOT be updated as if the edit succeeded

#### Scenario: Glossary edit on unavailable cache
- **WHEN** any `GlossaryService` mutation is invoked while `CacheService.isAvailable == false`
- **THEN** the call SHALL throw `CacheError.unavailable`
- **THEN** the database SHALL NOT be touched

### Requirement: Add, edit, and delete glossary terms
The system SHALL allow users to add new source→target term mappings, edit existing mappings, and delete individual terms within a glossary. Terms SHALL be displayed ordered by creation time, newest first (`ORDER BY created_at DESC`).

#### Scenario: User adds a term manually
- **WHEN** user taps "+ Add Term" and enters source and target text
- **THEN** the term is saved with `auto_detected = false` and appears at the top of the glossary term list

#### Scenario: User edits an existing term
- **WHEN** user selects a term and modifies source or target text
- **THEN** the updated mapping is persisted immediately

#### Scenario: User deletes a term
- **WHEN** user selects delete on a term
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
The system SHALL display a glossary selector in the main window toolbar that shows the active glossary name (or "Glossary" as the label when nothing is selected). Users SHALL be able to switch glossaries or clear the selection ("No Glossary") at any time without leaving the main window. The selection is session-only and resets to no glossary on app launch.

#### Scenario: User selects a glossary
- **WHEN** user opens the glossary picker and selects a named glossary
- **THEN** the toolbar reflects the selected name and subsequent translations use that glossary's terms

#### Scenario: User clears glossary selection
- **WHEN** user selects "No Glossary" in the glossary picker
- **THEN** subsequent translations proceed without glossary injection

### Requirement: Glossary management settings tab
The system SHALL provide a Glossary tab in the Settings window (positioned between Preferences and Debug) for managing glossaries. The Glossary tab SHALL display in `.formStyle(.grouped)` matching the visual style of other Settings tabs. It SHALL show a single-row glossary selector (Menu showing the active glossary name, or "Select a Glossary…" as placeholder when none is selected) with inline ✏️ (rename), ＋ (new), and 🗑 (delete) action buttons. Rename is confirmed via a sheet pre-filled with the current name. The terms list SHALL display in a separate section ordered newest first, with a ＋ button in the section header to add terms. Each term row SHALL show source → target text, an auto-detected badge where applicable, and edit/delete action buttons.

#### Scenario: User opens Glossary tab directly from toolbar
- **WHEN** user selects "Manage Glossaries..." from the main window toolbar glossary menu
- **THEN** the Settings window opens (or focuses if already open) and displays the Glossary tab

#### Scenario: User renames a glossary via the settings tab
- **WHEN** user taps the ✏️ rename button and enters a valid new name in the sheet
- **THEN** the glossary name is updated in the database and all pickers reflect the new name immediately

#### Scenario: User adds a term via the settings tab
- **WHEN** user taps the ＋ button in the Terms section header
- **THEN** a sheet appears to enter source and target text
- **AND** upon saving, the new term appears at the top of the terms list

#### Scenario: Terms displayed newest first
- **WHEN** user views the terms list in the settings tab
- **THEN** the most recently added term appears at the top of the list
