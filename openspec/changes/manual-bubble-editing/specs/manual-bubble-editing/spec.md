## ADDED Requirements

### Requirement: Edit mode lifecycle is per-page and explicit

The system SHALL expose a single per-page **Edit Mode** entered and exited only through explicit user actions surfaced in `TranslationSidebar`. An Edit Mode session SHALL be bound to exactly one page (identified by `MangaPage.id`).

The system SHALL render the Edit button as **enabled if and only if** the page's `PageState` is `.translated`. For `.pending`, `.processing`, and `.error` states the button SHALL be disabled (rendered but not interactive).

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
- **WHEN** the user views a page whose state is `.translated`
- **THEN** the Edit button in the sidebar header is enabled
- **AND** clicking it opens an Edit Mode session for that page

#### Scenario: Edit button disabled for non-translated states
- **WHEN** the page state is `.pending`, `.processing`, or `.error`
- **THEN** the Edit button is rendered but disabled
- **AND** no Edit Mode session can be opened

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

### Requirement: Drawing, moving, resizing, and deleting bubble boxes

While Edit Mode is active, the system SHALL support the following direct-manipulation operations on the image canvas:

- **Draw**: a primary-button drag that begins on canvas pixels not covered by any existing box's display rect SHALL create a new bounding box. The box SHALL have `isManual = true`. The drag-rectangle SHALL be clamped to image pixel bounds on every gesture update. On gesture end, if the resulting box has width or height < 20 image pixels, the system SHALL discard the box and SHALL NOT push an undo entry.

- **Move**: a primary-button drag that begins inside an existing box's body (outside the 16 pt corner handle zones and 8 pt edge handle zones) SHALL translate that box by the gesture delta. The resulting box SHALL be clamped to image pixel bounds. The box's `isManual` SHALL be set to `true` if it was `false`, regardless of how many subsequent moves occur.

- **Resize**: a primary-button drag that begins inside one of the 8 handle zones (4 corners + 4 edges) SHALL adjust the corresponding edge(s) of the box. The resulting box SHALL be clamped to image pixel bounds and SHALL have minimum width and height of 20 image pixels. The box's `isManual` SHALL be set to `true` if it was `false`.

- **Delete**: pressing `Delete` or `Backspace` while at least one box is selected SHALL stage all selected boxes for deletion. Staged-for-deletion boxes SHALL remain in the working copy (so undo can restore them) and SHALL be visually struck through; on Commit, staged-for-deletion boxes SHALL be removed.

`Esc` during an in-flight Draw, Move, or Resize gesture SHALL abort the gesture without recording an undo entry and without mutating any box.

Boxes are allowed to overlap. The system SHALL NOT merge, snap, or warn about overlapping boxes.

#### Scenario: Draw a new box
- **WHEN** the user drags from an empty canvas point (50, 60) to (200, 240) in image pixel coordinates
- **THEN** a new `BubbleCluster` is added with `boundingBox = (50, 60, 150, 180)` (clamped width 150, height 180)
- **AND** the new bubble has `isManual = true`
- **AND** an undo entry of type `.add` is recorded

#### Scenario: Drawn box below minimum size is discarded
- **WHEN** the user drags from (100, 100) to (115, 110), producing a 15×10 region
- **THEN** no `BubbleCluster` is added
- **AND** no undo entry is recorded

#### Scenario: Drawn box clamped to image bounds
- **WHEN** the image is 1000×1500 pixels and the user drags from (900, 1400) to (1200, 1700)
- **THEN** the resulting box has `boundingBox = (900, 1400, 100, 100)`

#### Scenario: Drawn box is positioned by nearest-neighbour insertion, not appended
- **WHEN** the working copy contains three bubbles with centres at `(100, 100)`, `(500, 100)`, `(100, 500)` and `index` values 0, 1, 2 respectively
- **AND** the user draws a new bubble with centre at `(120, 110)` (geometrically nearest to the bubble at index 0)
- **THEN** the working copy after the Draw contains four bubbles in array order: [original index 0, new bubble, original index 1, original index 2]
- **AND** every bubble's `index` is redensified to 0, 1, 2, 3 in array order
- **AND** the new bubble's resulting `index` is 1 (NOT 3, which would be the plain-append result)

#### Scenario: Move marks an auto box as manual
- **WHEN** the user drags an existing box whose `isManual` is `false` by (10, 0)
- **THEN** the box's `boundingBox.origin.x` increases by 10
- **AND** the box's `isManual` becomes `true`
- **AND** an undo entry of type `.move` with `from` and `to` rects is recorded

#### Scenario: Resize via corner handle
- **WHEN** the user drags the bottom-right corner handle of box B from (300, 400) to (350, 460)
- **THEN** the box's `boundingBox` width and height increase by 50 and 60 respectively
- **AND** the box's `isManual` is set to `true`
- **AND** an undo entry of type `.resize` is recorded

#### Scenario: Resize blocked below minimum dimensions
- **WHEN** the user drags a handle such that the resulting width or height would be less than 20 image pixels
- **THEN** the box dimension is clamped to 20 image pixels along that axis

#### Scenario: Delete via keyboard
- **WHEN** three boxes are selected and the user presses `Delete`
- **THEN** all three are staged for deletion (visually marked, still present in the working copy)
- **AND** a single undo entry of type `.multi([.delete, .delete, .delete])` is recorded

#### Scenario: Esc cancels in-flight gesture
- **WHEN** the user begins drawing a new box but presses `Esc` before releasing the mouse
- **THEN** no new box is created
- **AND** no undo entry is recorded

#### Scenario: Overlapping boxes allowed
- **WHEN** the user draws a new box whose rect overlaps 80% of an existing box
- **THEN** both boxes coexist in the working copy
- **AND** no merge, snap, or warning is produced

### Requirement: Selection model supports single and multi-select

The system SHALL maintain a current selection as a `Set<UUID>` keyed by `BubbleCluster.id`. The selection SHALL be updated by the following gestures while Edit Mode is active:

- **Click a box** (zero-distance drag inside its body): selection becomes exactly `{that.id}`.
- **Click on empty canvas**: selection becomes empty.
- **`Shift`+click a box**: that box's id is added to the selection.
- **`Cmd`+click a box**: if the box is in the selection, it is removed; otherwise it is added.
- **`Cmd+A`**: selection becomes the set of all non-deleted box ids in the working copy.
- **`Tab`**: selection becomes `{next-id}` where next is the box with `index` immediately greater than the highest currently-selected `index`, wrapping to lowest. If selection is empty, `Tab` selects the box with the lowest `index`.
- **`Shift+Tab`**: symmetric to `Tab`, decrementing.

Arrow-key nudging operates on every selected box:

- **`←` `→` `↑` `↓`**: shift the box's `boundingBox.origin` by 1 image pixel in the corresponding axis direction (right/down positive).
- **`Shift+`arrow**: shift by 10 image pixels.
- A single arrow-key press across N selected boxes produces a single grouped undo entry (`.multi([.move, ...])`), not N separate entries.

#### Scenario: Single click replaces selection
- **WHEN** selection is `{A, B}` and the user clicks box C
- **THEN** selection becomes `{C}`

#### Scenario: Shift-click adds to selection
- **WHEN** selection is `{A}` and the user shift-clicks B
- **THEN** selection becomes `{A, B}`

#### Scenario: Cmd-click toggles
- **WHEN** selection is `{A, B}` and the user Cmd-clicks B
- **THEN** selection becomes `{A}`

#### Scenario: Arrow-key nudge with multiple selection
- **WHEN** selection contains 4 boxes and the user presses `→`
- **THEN** every selected box's `boundingBox.origin.x` increases by 1
- **AND** each affected box's `isManual` is set to `true` if it was `false`
- **AND** a single undo entry is recorded covering all 4 moves

### Requirement: Undo and redo cover every edit action

The system SHALL maintain per-session undo and redo stacks of `EditAction` values. Every reversible mutation (add, delete, move, resize, reorder, grouped multi) SHALL push exactly one entry onto the undo stack at the moment the mutation is recorded as the user's intent (gesture end, key release, or sidebar drag end).

`Cmd+Z` SHALL pop the top entry from the undo stack, apply its inverse to the working copy, and push the original entry onto the redo stack.

`Cmd+Shift+Z` SHALL pop the top entry from the redo stack, apply it to the working copy, and push the original entry onto the undo stack.

Any new mutation SHALL clear the redo stack.

On Commit and on Cancel the system SHALL discard both stacks.

#### Scenario: Undo un-stages a deleted box
- **WHEN** the user deletes box B (with text "ABC", bbox (10, 10, 50, 50), index 3) — staging it for deletion
- **AND** the user presses `Cmd+Z`
- **THEN** box B's id is removed from `deletedBubbleIds`
- **AND** box B is still present in `workingBubbles` with the exact same id, text, bbox, index, and `isManual` value (because staged deletion never removed it from the working copy)
- **AND** the undo stack is one entry shorter
- **AND** the redo stack contains the original delete entry

#### Scenario: Redo re-stages a deleted box
- **WHEN** the user undoes a deletion and then presses `Cmd+Shift+Z`
- **THEN** box B's id is inserted back into `deletedBubbleIds` (staged for deletion again)
- **AND** the redo stack is empty
- **AND** the undo stack contains the delete entry

#### Scenario: New action clears redo stack
- **WHEN** the redo stack contains one entry and the user draws a new box
- **THEN** the redo stack becomes empty
- **AND** `Cmd+Shift+Z` does nothing

#### Scenario: Commit discards stacks
- **WHEN** the user commits a session with 5 undo entries and 2 redo entries
- **THEN** after the session ends both stacks contain zero entries
- **AND** subsequent `Cmd+Z` outside the session produces no edit-mode undo

### Requirement: Commit re-processes dirty bubbles and re-translates the page

On Commit, the system SHALL execute the following sequence. The terminal `(PageState, editSession)` pair is defined by an explicit state-transition table below; there is no other concept of atomicity. The pair is set together in a single `@MainActor` update at the end of each terminal branch — they are never observed in mixed intermediate combinations from the outside.

**Pipeline steps:**

1. Compute the **final working set** as `workingBubbles \ deletedBubbleIds`.
2. Recompute `index` over the final working set so values are dense `0..<n` in the user's current order.
3. **Empty-set short-circuit**: if the final working set is empty (the user deleted every bubble), the system SHALL skip OCR and SHALL NOT invoke `TranslationService.translate(...)`. It SHALL attempt to write `[]` to `CacheService` (best-effort, see step 10), then terminate via the **Empty** branch in the transition table below. The page SHALL NOT enter `.processing` on this branch — the operation is purely local and instantaneous from the user's perspective.
4. Classify each non-empty final-working-set bubble using a **single deterministic rule based on final geometry vs. snapshot**: a bubble is **OCR-dirty** if and only if (a) its `id` is not present in `originalSnapshot` (newly added) OR (b) its current `boundingBox` is not equal to its snapshot `boundingBox` (`CGRect.equalTo`, no tolerance). All other non-deleted bubbles are **OCR-clean** and reuse their snapshot `text`. This rule SHALL be evaluated at commit time and SHALL be the sole source of truth for OCR classification. Any in-session bookkeeping such as `dirtyBubbleIds` is purely a UI cache for displaying dirty visuals; it SHALL NOT be consulted. In particular, when the user moves a bubble and then `Cmd+Z`s back to the original position, the bubble is classified as **OCR-clean** at commit (because its current `boundingBox` equals snapshot), regardless of any UI-side dirty tracking.
5. Transition the page to `.processing` (only on the non-empty path).
6. Run the active OCR service over only the OCR-dirty bubbles' boxes on `page.image`. For each OCR-clean bubble, reuse its existing `text` from the snapshot.
7. Construct a single `[BubbleCluster]` containing every bubble in the final working set with text merged from step 6.
8. Build a `TranslationContext` using `summariesPreceding(pageIndex:)` for context-consuming engines, or empty `recentPageSummaries` for non-context engines.
9. Call `TranslationService.translate(bubbles:from:to:context:)` once for the page.
10. On translator success: attempt `CacheService.store(...)` with the new bubbles (best-effort; throws are logged via `DebugLogger` and swallowed), then terminate via the **Success** branch.
11. On OCR or translator failure (steps 6 or 9): terminate via the **Failure** branch. Cache is NOT written.

**Terminal state-transition table** — exactly one branch fires per Commit invocation:

| Branch | Trigger | Final `PageState` | Final `editSession` | Cache side effect |
|---|---|---|---|---|
| **Empty** | Step 3 (final set empty) | `.translated([])` | `nil` | best-effort write of `[]` (logged warning on throw) |
| **Success** | Step 9 returns non-throwing | `.translated(output.bubbles)` | `nil` | best-effort write of `output.bubbles` (logged warning on throw) |
| **Failure** | Step 6 (OCR) or Step 9 (translator) throws | `.error(<wrapped error>)` | unchanged (session stays open) | no write |

**During the pipeline (steps 5–9)** the page is in `.processing` and `editSession` remains non-nil. These are not observable terminal states; they exist only for the duration of the in-flight async work. From the user's perspective, every Commit transitions from `(.translated, session != nil)` directly into one of the three terminal rows above.

After **Failure**, the user retains the choice to:
- Press Done again to retry the Commit pipeline (which re-enters `.processing`).
- Press Cancel to discard the session, which restores `originalSnapshot` and `originalPageState` (clearing the `.error` per the lifecycle requirement above).

The Commit pipeline SHALL NOT issue a multi-page LLM batch request. The pipeline SHALL use the per-page `translate(...)` entry point even when the active engine supports batching.

#### Scenario: Commit with only new boxes
- **WHEN** the user added two new boxes and committed
- **THEN** OCR runs on exactly those two boxes
- **AND** translation runs over all bubbles on the page (including the new two and any pre-existing untouched ones)
- **AND** the cache entry is overwritten

#### Scenario: Commit with only deletions and reorders
- **WHEN** the user deleted one box and reordered the sidebar but made no geometry changes
- **THEN** OCR is not called
- **AND** translation runs over all remaining bubbles in the new order
- **AND** the cache entry is overwritten

#### Scenario: Commit with reorder-only and no other change
- **WHEN** the user only reordered bubbles and committed
- **THEN** OCR is not called
- **AND** translation runs over all bubbles in the new order
- **AND** the cache entry is overwritten with the new `index` values

#### Scenario: Commit failure keeps session open
- **WHEN** the translation step throws a network error during Commit
- **THEN** `page.state` becomes `.error(...)`
- **AND** `editSession` remains non-nil with the same working copy and undo stacks
- **AND** the Done and Cancel buttons remain available

#### Scenario: Undo-back-to-original yields OCR-clean classification
- **WHEN** the user moves an existing auto-detected bubble, then presses `Cmd+Z` so its `boundingBox` is byte-for-byte equal to its `originalSnapshot` `boundingBox`, then presses Done
- **THEN** the bubble is classified as OCR-clean
- **AND** OCR is not invoked for that bubble
- **AND** the translator receives the bubble's snapshot `text` unchanged
- **AND** the bubble's `isManual` remains `true` (sticky semantics — separate from OCR classification)

#### Scenario: Commit with empty final set skips OCR and translator
- **WHEN** the user deletes every bubble on the page and presses Done
- **THEN** the system does NOT call the OCR service for any bubble
- **AND** the system does NOT call `TranslationService.translate(...)`
- **AND** `page.state` becomes `.translated([])`
- **AND** the cache is overwritten with an empty bubble set (best-effort — see cache failure scenario)
- **AND** `editSession` is cleared
- **AND** the result is independent of whether an API key is configured or the network is available

#### Scenario: Cache write failure does not roll back a successful commit
- **WHEN** OCR and translation both succeed during Commit but `CacheService.store(...)` throws (e.g. SQLite locked, disk full)
- **THEN** a warning is logged via `DebugLogger`
- **AND** `page.state` becomes `.translated(output.bubbles)` (the in-memory commit succeeds)
- **AND** `editSession` is cleared
- **AND** no error UI is shown to the user for the cache failure alone

#### Scenario: Commit never uses multi-page batch
- **WHEN** the user commits an edit on page 5 with a context-consuming LLM engine active
- **THEN** the system invokes `TranslationService.translate(...)` for page 5 only
- **AND** the system does not group page 5 with any adjacent page into a batch request

### Requirement: BubbleCluster gains `isManual` flag with single-bit semantics

The `BubbleCluster` value type SHALL declare a stored property `isManual: Bool` with default value `false`.

The flag SHALL be set to `true` when:

- The bubble is created in an Edit Mode session via Draw.
- An auto-detected bubble's `boundingBox` is first modified during an Edit Mode session via Move, Resize, or arrow-key nudge.

The flag SHALL NOT be reset to `false` by any user action, including undo and redo. `isManual` records whether the user has ever touched the bubble's geometry within any committed or in-progress Edit Mode session; it is **not** a "current geometry differs from auto-detected" indicator. Once set to `true`, it remains `true` for the lifetime of the `BubbleCluster` (including after cache round-trip).

Reordering, deletion, undo, and redo SHALL NOT, by themselves, change `isManual` on any bubble that did not also undergo a geometry change. Undo of a Move or Resize SHALL restore the `boundingBox` to the prior value but SHALL NOT restore `isManual` to its prior value — the touch has happened, even if its geometric consequence is reverted.

#### Scenario: Drawn box is manual
- **WHEN** the user draws a new box
- **THEN** the bubble's `isManual` is `true`

#### Scenario: First move flips auto to manual
- **WHEN** an auto-detected bubble (`isManual = false`) is moved
- **THEN** the bubble's `isManual` becomes `true`

#### Scenario: Reorder alone does not change isManual
- **WHEN** the user drags a sidebar card to reorder, with no geometry change
- **THEN** no bubble's `isManual` value is modified

#### Scenario: Undo of move keeps isManual sticky
- **WHEN** an auto-detected bubble (`isManual = false`) is moved (becoming `isManual = true`) and the user then presses `Cmd+Z`
- **THEN** the bubble's `boundingBox` returns to the pre-move value
- **AND** the bubble's `isManual` remains `true`
- **AND** subsequent redo does not change `isManual` (it stays `true`)

#### Scenario: Cancel restores isManual to pre-session value
- **WHEN** an auto-detected bubble (`isManual = false`) is moved during a session and the user clicks Cancel
- **THEN** the original `[TranslatedBubble]` snapshot (taken at session start) is restored verbatim
- **AND** the bubble's `isManual` in the restored snapshot is `false` (its value before the session began)

### Requirement: Sidebar shows dirty visual state during edit

While Edit Mode is active, `TranslationSidebar` SHALL render each card with one of the following decorations:

- **Unchanged**: render as today (no decoration).
- **New (no OCR yet)**: replace the original-text and translated-text strings with the placeholder `"待處理"`, dim the card to 60% opacity, and mark the index badge with a `+` superscript.
- **Stale (geometry changed)**: strike through the original-text string and dim the translated-text string to 60% opacity; append a small `已修改` chip after the index badge.
- **Marked for deletion**: render the whole card with a red strikethrough overlay at 70% opacity.

Clicking a card that is marked for deletion SHALL un-stage that single bubble's deletion. The un-stage SHALL be implemented as a **new `.unstageDelete(bubble)` `EditAction`** that removes the bubble's id from `deletedBubbleIds`. Pushing this action SHALL follow the standard mutation flow: it is appended to the undo stack, it clears the redo stack, and it SHALL NOT mutate, rewrite, or remove any pre-existing `.delete` or `.multi` entry already on the stack. `deletedBubbleIds` is treated as a set (idempotent insert/remove), so subsequent undo/redo of the original delete entry (or its enclosing `.multi`) interacts correctly with the un-stage entry without double-counting.

Selection highlight SHALL coexist with every dirty decoration.

After Commit completes (success path), the sidebar SHALL render the new translated bubbles with no dirty decorations.

After Cancel, the sidebar SHALL render the original snapshot with no dirty decorations.

#### Scenario: New box shows placeholder
- **WHEN** the user draws a new box during edit
- **THEN** the corresponding sidebar card shows `"待處理"` in both original and translated text positions
- **AND** the card is dimmed
- **AND** the index badge shows `+`

#### Scenario: Geometry-changed box shows strikethrough
- **WHEN** the user resizes an existing translated box
- **THEN** the original text is rendered with strikethrough
- **AND** the translated text is dimmed
- **AND** a `已修改` chip appears next to the index badge

#### Scenario: Clicking a deletion-marked card un-stages it via a new action
- **WHEN** a card is marked for deletion and the user clicks it
- **THEN** the bubble's id is removed from `deletedBubbleIds`
- **AND** a new `.unstageDelete(bubble)` `EditAction` is pushed onto the undo stack
- **AND** the redo stack is cleared
- **AND** the original `.delete` or `.multi([.delete, ...])` entry that staged this deletion remains on the undo stack unchanged

#### Scenario: Partial un-stage inside a group delete survives undo/redo cycles
- **WHEN** the user deletes bubbles `{a, b, c, d, e}` in one shot (producing one `.multi([.delete, ...])` entry), then clicks card `c` to un-stage it
- **AND** the user then presses `Cmd+Z` once
- **THEN** the `.unstageDelete(c)` is reverted and `deletedBubbleIds` equals `{a, b, c, d, e}`
- **WHEN** the user presses `Cmd+Z` a second time
- **THEN** the `.multi` is reverted and `deletedBubbleIds` equals `{}`
- **WHEN** the user presses `Cmd+Shift+Z`
- **THEN** the `.multi` is re-applied and `deletedBubbleIds` equals `{a, b, c, d, e}`
- **AND** no bubble id appears twice or is missing at any step

### Requirement: Translation context for edit-commit re-translation

For an Edit Mode Commit that targets page N, the `TranslationContext.recentPageSummaries` passed to `TranslationService.translate(...)` SHALL be sourced from `summariesPreceding(pageIndex: N, count: 3)` when the active engine is a context-consuming LLM engine.

`summariesPreceding(pageIndex: N, count: K)` SHALL return up to K page summaries, drawn from pages whose page index is strictly less than N, taking the K closest such pages in ascending page-index order. A page SHALL contribute a summary if and only if it is currently in `.translated` state. Each summary SHALL be the concatenation of that page's `TranslatedBubble.translatedText` strings ordered by `TranslatedBubble.index`, joined by a single space.

For non-context engines (DeepL, Google), `recentPageSummaries` on the Commit path SHALL be empty.

The Commit-path `summariesPreceding` lookup SHALL NOT mutate the existing rolling window used by initial / batch translation.

#### Scenario: Edit on page 5 sees preceding pages
- **WHEN** the user commits an edit on page 5, the engine is OpenAI Compatible, and pages 2, 3, 4 are in `.translated` state
- **THEN** `recentPageSummaries` contains exactly three entries, corresponding to pages 2, 3, 4 in that order
- **AND** each entry is the concatenation of that page's translated bubble text in `index` order

#### Scenario: Edit on first page has no context
- **WHEN** the user commits an edit on page 0 (first page) with an LLM engine
- **THEN** `recentPageSummaries` is empty

#### Scenario: Edit skips untranslated preceding pages
- **WHEN** the user commits an edit on page 6 with an LLM engine, and pages 3, 5 are translated but page 4 is in `.error`
- **THEN** `recentPageSummaries` contains exactly two entries, in order: page 3's summary, page 5's summary

#### Scenario: Edit with DeepL has empty context
- **WHEN** the user commits an edit with DeepL as the active engine
- **THEN** `recentPageSummaries` is empty regardless of preceding page states
