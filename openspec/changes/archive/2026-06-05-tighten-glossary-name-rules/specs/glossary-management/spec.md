## MODIFIED Requirements

### Requirement: Create, rename, and delete glossaries
The system SHALL allow users to create named glossaries, rename existing glossaries, and delete existing glossaries along with all their terms. Glossary names SHALL be validated before create or rename persistence using these rules in order: leading and trailing whitespace/newlines are trimmed; empty or whitespace-only names are rejected with `GlossaryValidationError.emptyName`; names longer than 20 Swift `Character` values after trimming are rejected with `GlossaryValidationError.nameTooLong(max: 20)`; names that exactly match another glossary's normalized persisted name are rejected with `GlossaryValidationError.duplicateName`. Duplicate-name comparison SHALL be exact and case-sensitive using the trimmed candidate name and persisted glossary names. Rename SHALL ignore the glossary row being renamed when checking duplicates, so a rename to the same normalized name is valid when no other glossary has that name. No create or rename SQL SHALL be prepared or executed after a name validation failure. The delete operation SHALL be atomic: either both the `glossaries` row and every matching `glossary_terms` row are removed, or none of them are. The delete operation SHALL be implemented as an explicit SQLite transaction (`BEGIN IMMEDIATE` → delete from `glossary_terms` where `glossary_id` matches → delete from `glossaries` where `id` matches → `COMMIT`), with `ROLLBACK` on any failure. The schema SHALL NOT be migrated to add `ON DELETE CASCADE` or a unique glossary-name index.

#### Scenario: User creates a new glossary
- **WHEN** user taps "New Glossary" and enters a name that is non-empty after trimming, no longer than 20 Swift `Character` values after trimming, and not equal to any existing persisted glossary name
- **THEN** the name is trimmed
- **AND** a new glossary record is created using the trimmed name
- **AND** the new glossary becomes selectable in the glossary picker

#### Scenario: User creates a glossary with an empty name
- **WHEN** user submits an empty or whitespace-only glossary name
- **THEN** the system throws `GlossaryValidationError.emptyName` before executing SQL
- **AND** no glossary record is created

#### Scenario: User creates a glossary with name exceeding 20 characters
- **WHEN** user submits a glossary name whose trimmed value is longer than 20 Swift `Character` values
- **THEN** the system throws `GlossaryValidationError.nameTooLong(max: 20)` before executing SQL
- **AND** no truncated glossary record is created

#### Scenario: User creates a glossary with a duplicate name
- **WHEN** a glossary named "Characters" already exists
- **AND** user submits a new glossary name "  Characters  "
- **THEN** the system trims the submitted name to "Characters"
- **AND** the system throws `GlossaryValidationError.duplicateName` before executing SQL
- **AND** no glossary record is created

#### Scenario: Duplicate comparison is case-sensitive
- **WHEN** a glossary named "Characters" already exists
- **AND** user submits a new glossary name "characters"
- **THEN** the system treats the submitted name as distinct
- **AND** the create operation is allowed when all other name validation rules pass

#### Scenario: User renames a glossary successfully
- **WHEN** user enters a new name that is non-empty after trimming, no longer than 20 Swift `Character` values after trimming, and not equal to any other persisted glossary name
- **THEN** the name is trimmed
- **AND** the glossary's name is updated in the database using the trimmed name
- **AND** all UI pickers and references instantly reflect the updated name

#### Scenario: User renames a glossary to the same normalized name
- **WHEN** a glossary named "Characters" exists
- **AND** user renames that same glossary to "  Characters  "
- **AND** no other glossary is named "Characters"
- **THEN** the system treats the rename as valid
- **AND** the persisted name remains "Characters"

#### Scenario: User renames a glossary to an empty name
- **WHEN** user clears the name or enters only whitespace and confirms
- **THEN** the system throws `GlossaryValidationError.emptyName` before executing SQL
- **AND** the existing glossary name remains unchanged

#### Scenario: User renames a glossary with name exceeding 20 characters
- **WHEN** user submits a new glossary name whose trimmed value is longer than 20 Swift `Character` values
- **THEN** the system throws `GlossaryValidationError.nameTooLong(max: 20)` before executing SQL
- **AND** the existing glossary name remains unchanged
- **AND** no truncated glossary name is persisted

#### Scenario: User renames a glossary to a duplicate name
- **WHEN** glossaries named "Characters" and "Places" already exist
- **AND** user renames "Places" to "  Characters  "
- **THEN** the system trims the submitted name to "Characters"
- **AND** the system throws `GlossaryValidationError.duplicateName` before executing SQL
- **AND** both existing glossary names remain unchanged

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
The system SHALL make every `GlossaryService` mutation (`createGlossary`, `renameGlossary`, `deleteGlossary`, `addTerm`, `updateTerm`, `deleteTerm`, and any LLM auto-detected term insert) `throws`. A successful return SHALL mean the database has accepted the change. A thrown `GlossaryValidationError` SHALL identify invalid caller input and SHALL occur before SQL is executed. `GlossaryValidationError` SHALL include at least `emptyName`, `nameTooLong(max: Int)`, and `duplicateName` for glossary-name validation. A thrown `CacheError.sqlite` SHALL carry the SQLite result code and message and SHALL NOT silently leave partial state in either `glossaries` or `glossary_terms`. Read APIs (`listGlossaries`, `listTerms`) SHALL remain non-throwing.

#### Scenario: Rename validation fails before SQL
- **WHEN** `glossaryService.renameGlossary(id:newName:)` is invoked with an invalid glossary name
- **THEN** the call SHALL throw the corresponding `GlossaryValidationError`
- **AND** no SQL statement SHALL be prepared or executed for the rename
- **AND** the existing glossary name SHALL remain unchanged

#### Scenario: Create validation fails before SQL
- **WHEN** `glossaryService.createGlossary(name:)` is invoked with an invalid glossary name
- **THEN** the call SHALL throw the corresponding `GlossaryValidationError`
- **AND** no SQL statement SHALL be prepared or executed for the create
- **AND** no glossary record SHALL be inserted

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

### Requirement: Glossary management settings tab
The system SHALL provide a Glossary tab in the Settings window (positioned between Preferences and Debug) for managing glossaries. The Glossary tab SHALL display in `.formStyle(.grouped)` matching the visual style of other Settings tabs. It SHALL show a single-row glossary selector (Menu showing the active glossary name, or "Select a Glossary…" as placeholder when none is selected) with inline rename, new, and delete action buttons. Rename is confirmed via a sheet pre-filled with the current name. Create and rename sheets SHALL use the same glossary-name rules as `GlossaryService`: trimmed names must be non-empty, no longer than 20 Swift `Character` values, and not duplicate another glossary's persisted name. The sheets SHALL NOT enable confirmation when the current input is invalid. Empty-name validation feedback SHALL NOT be shown before the user edits the sheet field; after user interaction, empty input SHALL show specific validation feedback. Over-20-character and duplicate-name feedback SHALL be shown immediately for non-empty invalid input. The terms list SHALL display in a separate section ordered newest first, with a button in the section header to add terms. Each term row SHALL show source to target text, an auto-detected badge where applicable, and edit/delete action buttons.

#### Scenario: User opens Glossary tab directly from toolbar
- **WHEN** user selects "Manage Glossaries..." from the main window toolbar glossary menu
- **THEN** the Settings window opens (or focuses if already open) and displays the Glossary tab

#### Scenario: User creates a glossary via the settings tab
- **WHEN** user opens the create glossary sheet from the Glossary tab
- **AND** user enters a valid glossary name
- **AND** user confirms creation
- **THEN** the glossary name is persisted using the trimmed name
- **AND** the new glossary appears in the glossary selector
- **AND** the new glossary becomes the selected glossary

#### Scenario: Settings create sheet blocks invalid names
- **WHEN** user opens the create glossary sheet
- **THEN** the confirmation action is disabled
- **AND** empty-name validation feedback is not shown before the user edits the field
- **WHEN** user enters an empty, over-20-character, or duplicate glossary name in the create glossary sheet
- **THEN** the sheet displays validation feedback for the specific invalid condition after the interaction rules allow it
- **AND** the confirmation action remains disabled
- **AND** no glossary record is created

#### Scenario: User renames a glossary via the settings tab
- **WHEN** user taps the rename button and enters a valid new name in the sheet
- **THEN** the glossary name is updated in the database using the trimmed name
- **AND** all pickers reflect the new name immediately

#### Scenario: Settings rename sheet blocks invalid names
- **WHEN** user opens the rename glossary sheet with the current valid name pre-filled
- **THEN** validation feedback is not shown
- **WHEN** user enters an empty, over-20-character, or duplicate glossary name in the rename glossary sheet
- **THEN** the sheet displays validation feedback for the specific invalid condition after the interaction rules allow it
- **AND** the confirmation action is disabled
- **AND** the existing glossary name remains unchanged

#### Scenario: User adds a term via the settings tab
- **WHEN** user taps the add button in the Terms section header
- **THEN** a sheet appears to enter source and target text
- **AND** upon saving, the new term appears at the top of the terms list

#### Scenario: Terms displayed newest first
- **WHEN** user views the terms list in the settings tab
- **THEN** the most recently added term appears at the top of the list
