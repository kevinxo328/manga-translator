## MODIFIED Requirements

### Requirement: Sort bubbles by manga reading order
The system SHALL sort detected bubbles in manga reading order: right-to-left, top-to-bottom. Bubbles SHALL be partitioned into rows by vertical overlap, then each row sorted right-to-left by horizontal position.

#### Scenario: Simple grid layout
- **WHEN** four bubbles are detected at positions: top-left, top-right, bottom-left, bottom-right
- **THEN** the reading order is: top-right → top-left → bottom-right → bottom-left

#### Scenario: Bubbles at different heights
- **WHEN** bubble A is at (x:800, y:100) and bubble B is at (x:200, y:120), with overlapping Y ranges
- **THEN** they are in the same row, ordered A → B (right to left)

### NEW Requirement: Manual bubble reorder
The system SHALL allow users to manually reorder translated bubbles via drag-and-drop in the translation sidebar. After reordering, the system SHALL reassign sequential indices (0, 1, 2, ...) to reflect the new order. The reorder SHALL be reflected immediately in both the sidebar display numbers and the image viewer bubble badges. The reorder SHALL be persisted to cache.

#### Scenario: Drag bubble from position 2 to position 0
- **WHEN** three bubbles exist in order [A, B, C] and user drags C to the top
- **THEN** the order becomes [C, A, B] with indices [0, 1, 2]

#### Scenario: Reorder persists across page switches
- **WHEN** user reorders bubbles on page 1, navigates to page 2, then back to page 1
- **THEN** page 1 shows the reordered sequence (from cache)

#### Scenario: ImageViewer badges update after reorder
- **WHEN** user reorders bubbles in the sidebar
- **THEN** the numbered badges on the image viewer update to match the new order

### NEW Requirement: BubbleReorder pure function
The system SHALL provide a pure function `BubbleReorder.move(bubbles:from:to:)` that takes a list of `TranslatedBubble`, a source position, and a target position, and returns a new list with the item moved and all indices reassigned sequentially. Invalid positions (negative, out of bounds, same position) SHALL return the original list unchanged.

#### Scenario: Move middle to first
- **WHEN** `move(bubbles: [A(0), B(1), C(2)], from: 1, to: 0)` is called
- **THEN** result is `[B(0), A(1), C(2)]`

#### Scenario: Invalid source position
- **WHEN** `move(bubbles: [A(0), B(1)], from: -1, to: 0)` is called
- **THEN** result is `[A(0), B(1)]` unchanged

#### Scenario: Same position
- **WHEN** `move(bubbles: [A(0), B(1)], from: 1, to: 1)` is called
- **THEN** result is `[A(0), B(1)]` unchanged

### MODIFIED Requirement: Re-translate preserves bubble order
The system SHALL re-translate pages without re-running OCR. When the user triggers re-translate (single page or all pages), the system SHALL reuse the existing `BubbleCluster` objects and their current indices, and only re-send them to the translation API. If the page has not been translated yet, the system SHALL fall back to the full OCR + translate pipeline. If re-translation fails, the system SHALL restore the previous translation result.

#### Scenario: Re-translate current page preserves manual reorder
- **WHEN** user reorders bubbles then triggers re-translate
- **THEN** the bubbles are sent to the translation API in the reordered sequence, and the result preserves the same order

#### Scenario: Re-translate all pages preserves order
- **WHEN** user triggers re-translate all pages
- **THEN** each page's existing bubble order is preserved during re-translation

#### Scenario: Re-translate untranslated page falls back to full pipeline
- **WHEN** a page is in `.pending` state and re-translate is triggered
- **THEN** the system runs the full OCR + translate pipeline

#### Scenario: Re-translate failure restores previous result
- **WHEN** the translation API fails during re-translate
- **THEN** the page returns to its previous translated state, not an error state

### REMOVED Requirement: LLM-assisted order correction
LLM-assisted reading order correction is removed. The system now relies on geometric sorting plus manual user correction. The LLM translation prompt continues to instruct "echo back index unchanged".
