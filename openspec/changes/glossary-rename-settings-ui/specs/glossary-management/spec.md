## MODIFIED Requirements

### Requirement: Create and delete glossaries
The system SHALL allow users to create named glossaries, rename existing glossaries, and delete existing glossaries along with all their terms. Glossary names SHALL be normalized before create or rename persistence: leading and trailing whitespace/newlines are trimmed, empty or whitespace-only names are rejected with a structured validation error before SQL is executed, and names longer than 20 Swift `Character` values are truncated to the first 20 characters before SQL is executed. The delete operation SHALL be atomic: either both the `glossaries` row and every matching `glossary_terms` row are removed, or none of them are. The delete operation SHALL be implemented as an explicit SQLite transaction (`BEGIN IMMEDIATE` → delete from `glossary_terms` where `glossary_id` matches → delete from `glossaries` where `id` matches → `COMMIT`), with `ROLLBACK` on any failure. The schema SHALL NOT be migrated to add `ON DELETE CASCADE`.

#### Scenario: User creates a new glossary
- **WHEN** user taps "New Glossary" and enters a name
- **THEN** the name is normalized according to the glossary-name rules
- **AND** a new glossary record is created and becomes selectable in the glossary picker

#### Scenario: User creates a glossary with an empty name
- **WHEN** user submits an empty or whitespace-only glossary name
- **THEN** the system throws a structured validation error before executing SQL
- **AND** no glossary record is created

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

#### Scenario: User renames a glossary successfully
- **WHEN** user enters a new valid name (non-empty, up to 20 characters) and submits the change
- **THEN** the name is normalized according to the glossary-name rules
- **THEN** the glossary's name is updated in the database
- **THEN** all UI pickers and references instantly reflect the updated name

#### Scenario: User renames a glossary to an empty name
- **WHEN** user clears the name or enters only whitespaces
- **THEN** the system throws a structured validation error before executing SQL
- **AND** the existing glossary name remains unchanged

#### Scenario: User renames a glossary with name exceeding 20 characters
- **WHEN** user inputs a name longer than 20 characters
- **THEN** the system truncates the input at 20 characters before saving
- **AND** the persisted glossary name contains exactly the first 20 Swift `Character` values of the trimmed input

### Requirement: Glossary mutations report failure to the caller
The system SHALL make every `GlossaryService` mutation (`createGlossary`, `renameGlossary`, `deleteGlossary`, `addTerm`, `updateTerm`, `deleteTerm`, and any LLM auto-detected term insert) `throws`. A successful return SHALL mean the database has accepted the change. A thrown SQLite error SHALL carry the SQLite result code and message and SHALL NOT silently leave partial state in either `glossaries` or `glossary_terms`. A thrown validation error SHALL identify invalid caller input and SHALL occur before SQL is executed. Read APIs (`listGlossaries`, `listTerms`) SHALL remain non-throwing.

#### Scenario: Glossary rename validation fails before SQL
- **WHEN** `glossaryService.renameGlossary(id:newName:)` is invoked with an empty or whitespace-only name
- **THEN** the call SHALL throw a structured validation error
- **AND** no SQL statement SHALL be prepared or executed
- **AND** the existing glossary name SHALL remain unchanged

## ADDED Requirements

### Requirement: Glossary management settings tab
The system SHALL provide a unified Glossary tab in the Settings window for managing glossaries. The Glossary tab SHALL display in `.formStyle(.grouped)` matching the visual style of other Settings tabs. It SHALL list all glossaries via a picker, allow switching the active glossary, support inline renaming with focus management, and provide full CRUD for both glossaries and their terms. Inline rename SHALL mirror the glossary-name normalization rules: input is kept to at most 20 characters for immediate feedback, empty trimmed input cannot be committed, and submitting or losing focus commits a changed normalized value. Each term SHALL display its source text, target text, and whether it was auto-detected in a native form section row layout with edit/delete actions.

#### Scenario: View and edit terms in settings
- **WHEN** user opens the Glossary tab in settings and selects a glossary
- **THEN** the list of terms is displayed as native form rows inside a grouped section
- **AND** manually created and auto-detected terms are visually distinguished
- **AND** each row supports editing or deleting the term directly

#### Scenario: Inline rename commits once
- **WHEN** user edits the active glossary name and presses Enter
- **AND** the field later loses focus without further changes
- **THEN** the system persists the normalized name at most once
- **AND** the active glossary picker reflects the renamed glossary

## REMOVED Requirements

### Requirement: Glossary management sheet
The system SHALL provide a modal sheet accessible from the toolbar for managing glossaries. The sheet SHALL list all glossaries, allow switching the active glossary, and provide full CRUD for both glossaries and their terms. Each term SHALL display its source text, target text, and whether it was auto-detected.

#### Scenario: Sheet shows auto-detected vs manual terms
- **WHEN** user opens the glossary management sheet
- **THEN** auto-detected terms are visually distinguished (e.g., a label or icon) from manually entered terms
