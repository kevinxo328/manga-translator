## ADDED Requirements

### Requirement: Pipeline-affecting controls locked while translation is in flight
The system SHALL treat translation as in flight when the batch pipeline is running (the view model's `isProcessing` flag, set exclusively by the batch pipeline) OR when any page's state is `.processing` (single-page flows: initial single-image translation, sidebar Re-translate, engine switch, Edit Mode commit).

While translation is in flight, the system SHALL disable every main-window toolbar control whose activation would mutate translation settings, replace the loaded pages, or start a competing translation flow:

- the Open button
- the glossary picker
- the source and target language pickers
- the translation engine picker
- the Re-translate All button

While batch translation is running, the sidebar Re-translate and Edit buttons SHALL also be disabled regardless of the current page's own state. (Outside batch, these buttons keep their existing per-page gating: a single-page flow on one page does not lock them for other pages.)

Page navigation controls (previous/next buttons, page indicator, keyboard navigation) SHALL remain enabled, preserving the existing "browse while translating" behavior.

All disabled controls SHALL re-enable when no translation remains in flight (every page has left `.processing` and the batch pipeline has finished — success, failure, or cancellation).

Batch translation and Edit Mode SHALL be mutually exclusive in both directions: while batch translation is running no Edit Mode session can be opened (sidebar Edit disabled, above), and while an Edit Mode session is open no batch can start — the Re-translate All button, the Open button, and file drag-and-drop SHALL be inert during an edit session, so the batch pipeline can never reach a page whose edit session is still uncommitted.

#### Scenario: Batch cannot start while an Edit Mode session is open
- **WHEN** an Edit Mode session is active on any page
- **THEN** the Re-translate All button and the Open button are disabled and dropped files are ignored
- **AND** no batch pipeline starts until the session is committed or cancelled

#### Scenario: Toolbar controls disabled during batch
- **WHEN** batch translation is running
- **THEN** the Open button, glossary picker, source/target language pickers, engine picker, and Re-translate All button are disabled

#### Scenario: Toolbar controls disabled during single-page translation
- **WHEN** no batch is running and a single page is being translated (its state is `.processing`, e.g. after pressing the sidebar Re-translate button on a single image)
- **THEN** the Open button, glossary picker, source/target language pickers, engine picker, and Re-translate All button are disabled
- **AND** they re-enable when that page reaches `.translated` or `.error`

#### Scenario: Sidebar actions disabled during batch even on a translated page
- **WHEN** batch translation is running and the currently viewed page has already reached `.translated`
- **THEN** the sidebar Re-translate and Edit buttons are disabled

#### Scenario: Navigation stays enabled during batch
- **WHEN** batch translation is running
- **THEN** the user can still navigate between pages with the previous/next buttons and arrow keys

#### Scenario: Controls re-enable when batch finishes
- **WHEN** the batch pipeline completes for all pages (regardless of per-page success or failure)
- **THEN** all controls listed above become enabled again, subject to their other gating conditions (e.g. Edit still requires a `.translated` page)
