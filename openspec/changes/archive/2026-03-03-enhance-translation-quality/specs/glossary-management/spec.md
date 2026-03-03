## ADDED Requirements

### Requirement: Glossary persistence
The system SHALL store glossaries and their terms in the existing SQLite cache database using two tables: `glossaries` (id, name, created_at) and `glossary_terms` (id, glossary_id, source_term, target_term, auto_detected, created_at). Glossaries are language-agnostic — there is no source/target language binding; the user chooses which glossary to apply regardless of the current translation direction. The system SHALL use `CREATE TABLE IF NOT EXISTS` to remain safe on existing installs.

#### Scenario: Tables created on first launch after update
- **WHEN** the app launches and the glossary tables do not exist
- **THEN** the system creates `glossaries` and `glossary_terms` tables without affecting existing cache data

### Requirement: Create and delete glossaries
The system SHALL allow users to create named glossaries (requiring a non-empty name) and delete existing glossaries along with all their terms.

#### Scenario: User creates a new glossary
- **WHEN** user taps "New Glossary" and enters a name
- **THEN** a new glossary record is created and becomes selectable in the glossary picker

#### Scenario: User deletes a glossary
- **WHEN** user selects "Delete Glossary" and confirms the alert
- **THEN** the glossary and all its terms are removed from the database

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
