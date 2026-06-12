## Purpose

Multi-page manga processing: folder/archive loading, background translation, and page navigation.

## Requirements

### Requirement: Open folders containing manga images
The system SHALL allow users to open a folder. The system SHALL scan the folder for image files (jpg, png, gif, webp, bmp) and sort them by filename for page ordering.

#### Scenario: Open manga folder
- **WHEN** user opens a folder containing 30 .jpg files named page_001.jpg through page_030.jpg
- **THEN** the system loads them as a 30-page manga, ordered by filename

### Requirement: Open compressed archives
The system SHALL support opening .zip and .cbz files. The system SHALL extract image files to a temporary directory within the sandbox container and treat them as a folder of pages.

#### Scenario: Open .cbz archive
- **WHEN** user opens a .cbz file containing manga pages
- **THEN** the system extracts images, sorts by filename, and presents as a multi-page manga

### Requirement: Progressive background translation
The system SHALL translate pages in the background using Swift concurrency. Pages SHALL become viewable as soon as their translation completes. The system SHALL limit concurrent translation tasks to avoid API rate limits.

#### Scenario: Browse while translating
- **WHEN** user opens a 30-page manga and translation begins
- **THEN** user can navigate to any page; completed pages show translations, pending pages show the original image with a loading indicator

#### Scenario: Concurrent translation limit
- **WHEN** batch translation is running
- **THEN** no more than 3 pages are being translated simultaneously

### Requirement: Deterministic page state transitions under async OCR
The system SHALL keep page state transitions deterministic when OCR executes asynchronously during batch translation. Each page SHALL move through `pending` → `processing` → (`translated` | `error`) with every transition occurring exactly once and no intermediate invalid state. OCR compute for each page SHALL execute outside the UI-critical execution context while page state updates continue to flow through the UI state channel.

#### Scenario: Batch translation does not block UI
- **WHEN** a user starts batch translation with multiple pages and high-accuracy OCR enabled
- **THEN** OCR compute for each page runs outside the UI-critical execution context while page state updates continue through the UI state channel

#### Scenario: Successful async OCR completion
- **WHEN** asynchronous OCR completes successfully for a page
- **THEN** the page transitions from `processing` to `translated` exactly once with no intermediate invalid state

#### Scenario: Async OCR failure
- **WHEN** asynchronous OCR fails for a page
- **THEN** the page transitions from `processing` to `error` exactly once and surfaces the OCR error message

### Requirement: Page navigation
The system SHALL provide page navigation controls (previous/next buttons, page number indicator) when viewing multi-page manga. Keyboard shortcuts (left/right arrow keys) SHALL also navigate pages.

#### Scenario: Navigate pages
- **WHEN** user is on page 5 of 30 and presses the right arrow key
- **THEN** the view advances to page 6

#### Scenario: Page indicator
- **WHEN** user is viewing a multi-page manga
- **THEN** the UI shows "Page 5/30" with translation status (e.g., "Page 5/30 - Translated" or "Page 5/30 - Translating...")

### Requirement: Batch translation progress
The system SHALL display overall batch progress (e.g., "12/30 pages translated") during batch processing.

#### Scenario: Progress display
- **WHEN** 12 of 30 pages have been translated
- **THEN** the UI shows "12/30 pages translated"

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
