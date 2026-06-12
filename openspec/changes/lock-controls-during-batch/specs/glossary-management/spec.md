## MODIFIED Requirements

### Requirement: Glossary picker in main UI
The system SHALL display a glossary selector in the main window toolbar that shows the active glossary name (or "Glossary" as the label when nothing is selected). Users SHALL be able to switch glossaries or clear the selection ("No Glossary") at any time without leaving the main window, except while translation is in flight (batch or single-page), during which the picker SHALL be disabled (see `batch-processing` — Pipeline-affecting controls locked while translation is in flight). The selection is session-only and resets to no glossary on app launch.

#### Scenario: User selects a glossary
- **WHEN** user opens the glossary picker and selects a named glossary
- **THEN** the toolbar reflects the selected name and subsequent translations use that glossary's terms

#### Scenario: User clears glossary selection
- **WHEN** user selects "No Glossary" in the glossary picker
- **THEN** subsequent translations proceed without glossary injection

#### Scenario: Glossary picker disabled while translation is in flight
- **WHEN** batch translation is running, or any page is in `.processing` from a single-page translation flow
- **THEN** the glossary picker is disabled and the active glossary cannot change until no translation remains in flight
