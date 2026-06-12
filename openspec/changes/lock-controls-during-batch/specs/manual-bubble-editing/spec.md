## MODIFIED Requirements

### Requirement: Edit mode lifecycle is per-page and explicit

The system SHALL expose a single per-page **Edit Mode** entered and exited only through explicit user actions surfaced in `TranslationSidebar`. An Edit Mode session SHALL be bound to exactly one page (identified by `MangaPage.id`).

The system SHALL render the Edit button as **enabled if and only if** the page's `PageState` is `.translated` AND no batch translation is running (the view model's `isProcessing` flag is false; see `batch-processing` — Pipeline-affecting controls locked while translation is in flight). For `.pending`, `.processing`, and `.error` states, and while batch translation is running, the button SHALL be disabled (rendered but not interactive).

Entering Edit Mode SHALL capture an immutable snapshot of the current page's `[TranslatedBubble]` and instantiate a working copy used for all in-session mutations. The original `[TranslatedBubble]` SHALL not be mutated during the session.

Exiting Edit Mode SHALL occur via exactly one of:

- **Commit (Done)**, triggered by the Done button or `Cmd+Return`.
- **Cancel**, triggered by the Cancel button, `Cmd+.`, or by `Esc` resolving through its priority cascade: `Esc` SHALL first abort any in-flight Draw/Move/Resize gesture; otherwise SHALL clear the current selection if non-empty; otherwise (no in-flight gesture AND empty selection) SHALL trigger Cancel.
- **Window close attempt** while editing is active SHALL be intercepted; the system SHALL block the close and surface a single non-modal hint (e.g. shake the Done/Cancel buttons) prompting the user to commit or cancel. The system SHALL NOT auto-commit and SHALL NOT auto-cancel on window close.

In addition to capturing `[TranslatedBubble]`, the system SHALL capture the page's `PageState` at session open (always `.translated`, per the gating rule above) and SHALL restore that PageState on Cancel. This rule applies even when an in-session Commit has previously failed and left the page in `.error`: a subsequent Cancel SHALL restore the page to `.translated` with the original `[TranslatedBubble]`, clearing the error.

While Edit Mode is active the system SHALL disable page-switching: next/previous page controls and sidebar thumbnail clicks SHALL be inert.

**Arrow-key routing in Edit Mode** SHALL follow this priority cascade (top to bottom; the first matching rule wins):

1. ←/→/↑/↓ SHALL NEVER trigger page navigation while Edit Mode is active. The page-navigation handler (which consumes ←/→ outside Edit Mode) MUST check the edit-active flag first and decline to handle the event when active.
2. If the current selection is non-empty, the arrow key SHALL nudge every selected bubble by 1 image pixel in the corresponding axis (or 10 px with `Shift`), per the selection-model requirement below.
3. If the current selection is empty and no in-flight gesture exists, the arrow key SHALL be ignored (no-op).

The system SHALL NOT display a modal alert for blocked page switches.

#### Scenario: Edit button gated by page state
- **WHEN** the user views a page whose state is `.translated` and no batch translation is running
- **THEN** the Edit button in the sidebar header is enabled
- **AND** clicking it opens an Edit Mode session for that page

#### Scenario: Edit button disabled for non-translated states
- **WHEN** the page state is `.pending`, `.processing`, or `.error`
- **THEN** the Edit button is rendered but disabled
- **AND** no Edit Mode session can be opened

#### Scenario: Edit button disabled during batch translation
- **WHEN** batch translation is running and the currently viewed page has already reached `.translated`
- **THEN** the Edit button is rendered but disabled
- **AND** it re-enables when the batch finishes (the page still being `.translated`)

#### Scenario: Cancel restores pre-edit state byte-for-byte
- **WHEN** the user enters Edit Mode and performs add, delete, move, and reorder actions
- **AND** the user clicks Cancel
- **THEN** the page's `[TranslatedBubble]` equals the snapshot captured at session start, in the same order
- **AND** the page state returns to `.translated`
- **AND** no cache write occurs

#### Scenario: Page-switch UI disabled during edit
- **WHEN** Edit Mode is active for page 5 of 20
- **THEN** the next-page button, previous-page button, and sidebar thumbnails for other pages are non-interactive
- **AND** pressing the left or right arrow key with empty selection produces no page change AND no nudge
- **AND** pressing the left or right arrow key with at least one selected bubble nudges the selection (still no page change)

#### Scenario: Window close intercepted during edit
- **WHEN** Edit Mode is active and the user clicks the window's close button
- **THEN** the window does not close
- **AND** no Cancel and no Commit is triggered
- **AND** the session remains open

#### Scenario: Esc aborts in-flight gesture without exiting edit mode
- **WHEN** the user has started but not released a Draw, Move, or Resize gesture
- **AND** the user presses `Esc`
- **THEN** the gesture is aborted with no `EditAction` recorded
- **AND** the edit session remains open
- **AND** the selection is unchanged

#### Scenario: Esc clears non-empty selection without exiting edit mode
- **WHEN** no gesture is in flight, the current selection contains one or more boxes, and the user presses `Esc`
- **THEN** the selection becomes empty
- **AND** the edit session remains open
- **AND** no Cancel occurs

#### Scenario: Esc with no gesture and empty selection triggers Cancel
- **WHEN** no gesture is in flight, the selection is empty, and the user presses `Esc`
- **THEN** the system performs Cancel (restoring `originalSnapshot` and `originalPageState`)
- **AND** the edit session ends

#### Scenario: Cancel after a failed Commit restores translated state
- **WHEN** the user enters Edit Mode on a `.translated` page, performs edits, presses Done, the translation step throws an error and the page transitions to `.error` with the session kept open
- **AND** the user then clicks Cancel
- **THEN** the page's `[TranslatedBubble]` equals the snapshot captured at session start
- **AND** the page state returns to `.translated` (not `.error`)
- **AND** the Edit button becomes enabled again
- **AND** no cache write occurs
