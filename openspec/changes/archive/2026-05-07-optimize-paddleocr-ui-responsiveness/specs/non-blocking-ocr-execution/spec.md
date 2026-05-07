## ADDED Requirements

### Requirement: OCR compute MUST NOT block UI-critical execution
The system MUST execute OCR-heavy computation outside the UI-critical execution context so that high-accuracy OCR does not stall the app interface during translation.

#### Scenario: Single-page translation with high-accuracy OCR
- **WHEN** a user translates a page while high-accuracy OCR is enabled
- **THEN** OCR compute runs outside the UI-critical execution context and the UI remains responsive to user interaction

#### Scenario: Batch translation with high-accuracy OCR
- **WHEN** a user starts batch translation with multiple pages and high-accuracy OCR enabled
- **THEN** OCR compute for each page runs outside the UI-critical execution context while page state updates continue through the UI state channel

### Requirement: UI state updates MUST remain deterministic under async OCR
The system MUST keep page-state transitions deterministic when OCR executes asynchronously, including `pending`, `processing`, `translated`, and `error` transitions.

#### Scenario: Successful async OCR completion
- **WHEN** asynchronous OCR completes successfully for a page
- **THEN** the page transitions from `processing` to `translated` exactly once with no intermediate invalid state

#### Scenario: Async OCR failure
- **WHEN** asynchronous OCR fails for a page
- **THEN** the page transitions from `processing` to `error` exactly once and surfaces the OCR error message
