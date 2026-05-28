## ADDED Requirements

### Requirement: Nearest-neighbour insertion for newly added boxes

`ReadingOrderSorter` SHALL expose an operation `insertNearestNeighbour(_ newBox: BubbleCluster, into ordered: [BubbleCluster]) -> [BubbleCluster]` that places a single new bubble into an already-ordered array without re-sorting any existing entries.

The operation SHALL behave as follows:

1. If `ordered` is empty, return `[newBox]` with `index = 0`.
2. Otherwise, compute the Euclidean distance between `newBox.boundingBox`'s centre and every entry's `boundingBox` centre in image pixel coordinates.
3. Let `nearest` be the entry with the smallest distance. Ties SHALL be broken by smaller `(boundingBox.midY, boundingBox.midX)` of the candidate's centre (ascending lexicographic).
4. Insert `newBox` into `ordered` at the position **immediately after** `nearest`.
5. Recompute every entry's `index` as its array position (`0..<n`) and return the result.

The operation SHALL be deterministic for any given input and SHALL NOT consult or mutate any global state.

The operation SHALL NOT reorder any pre-existing entry beyond shifting indices forward by 1 for entries after the insertion point.

#### Scenario: Insert into empty order
- **WHEN** `insertNearestNeighbour(N, into: [])` is called
- **THEN** the result is `[N]` with `N.index == 0`

#### Scenario: Insert after the nearest neighbour
- **WHEN** `ordered` contains boxes with centres at `(100, 100)`, `(500, 100)`, `(100, 500)`, in that order with indices 0, 1, 2
- **AND** `newBox` has centre at `(120, 110)` (nearest to the first box)
- **THEN** the result is `[ordered[0], newBox, ordered[1], ordered[2]]`
- **AND** the indices are reassigned to 0, 1, 2, 3

#### Scenario: Tie broken by lower (midY, midX)
- **WHEN** `newBox`'s centre is equidistant from two candidates A at `(100, 200)` and B at `(200, 100)`
- **THEN** B is selected as the nearest neighbour (because B's `midY = 100` is less than A's `midY = 200`)

#### Scenario: Pre-existing order is preserved otherwise
- **WHEN** the existing array reflects a user's manual reorder that differs from geometric order
- **AND** a new box is inserted via `insertNearestNeighbour`
- **THEN** the relative order of every pair of pre-existing boxes is unchanged
- **AND** only one new entry has been added to the array

### Requirement: Reading order accepts user-supplied manual ordering

The system SHALL treat reading order as a per-page property that may be sourced from either `ReadingOrderSorter.sort(...)` (initial auto-detection path) or from user input (Edit Mode reorder via sidebar drag-and-drop, or commit of an edit session that contains reorder actions).

A user-supplied order, once committed, SHALL be persisted as `BubbleCluster.index` values in `0..<n` matching the user's chosen sequence, and SHALL NOT be overwritten by a subsequent re-run of `ReadingOrderSorter.sort(...)` triggered by an Edit Mode Commit.

`ReadingOrderSorter.sort(...)` SHALL continue to be used only on initial detection (no prior translated state to preserve).

#### Scenario: Manual reorder survives commit
- **WHEN** the user enters Edit Mode, reorders three bubbles in the sidebar (no geometry edits), and commits
- **THEN** the committed `[TranslatedBubble]` retains the user's order
- **AND** the sequence is NOT replaced by a geometric re-sort
- **AND** `index` values are dense `0..<n` in the user's chosen order

#### Scenario: Initial detection still uses geometric sort
- **WHEN** a new page is detected for the first time (no prior translated state)
- **THEN** `ReadingOrderSorter.sort(...)` produces the initial order
- **AND** no manual order is consulted
