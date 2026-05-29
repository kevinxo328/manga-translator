## Context

`TranslationViewModel` (31 KB, `@MainActor`) drives a one-shot pipeline: `ComicTextDetectorService` → `MangaOCRRecognizer` / PaddleOCR → `TranslationService.translate(...)`. The output is an immutable `[TranslatedBubble]` rendered by `ImageViewer` and `TranslationSidebar`. There is no current mechanism for the user to mutate `BubbleCluster.boundingBox`, add new bubbles, or reorder reading sequence after the fact.

This change introduces a transactional **edit session** scoped to a single page. The session is opened explicitly by the user, mutates a working copy of the page's bubbles, and on commit produces a new `[TranslatedBubble]` through the same OCR + translation services. Cache, downstream views, and the existing batch pipeline must remain correct in the presence of manually authored bubbles.

Constraints:
- Swift 6 concurrency: `TranslationViewModel` is `@MainActor`; edit-session state lives on the view model and is mutated only on the main actor.
- `BubbleCluster` is currently a `struct` with value semantics; mutation is by reassignment.
- `CacheService` persists `TranslatedBubble` as JSON keyed by `(image_hash, source_lang, target_lang, engine)`; schema must remain backward-readable.
- `ReadingOrderSorter` is pure geometric (right-to-left, top-to-bottom row partition). Once a user reorders or inserts, the sorter is no longer authoritative for that page.

## Goals / Non-Goals

**Goals:**
- A user can correct any detection error on a translated page (missed bubble, mis-framed bubble, false positive, wrong reading order) and re-process only what changed, without losing work on adjacent pages.
- Edit sessions are transactional: every in-progress change is either fully committed or fully discarded — never partially applied.
- The data model carries enough information (`isManual`) for future logic (e.g. "do not re-run detector over user-authored regions") without requiring further migration.
- Edit-mode interaction follows macOS conventions (`Cmd+Z`, `Delete`, `Esc`, multi-select with `Shift`/`Cmd`).

**Non-Goals:**
- Editing multiple pages simultaneously. Each session is single-page.
- Rotated or non-axis-aligned bounding boxes. `boundingBox` stays `CGRect`.
- Manual OCR override (typing text into a box without OCR). Out of scope.
- Manual translation override (editing the translated text). Already covered by future work, not this change.
- Editing while a page is `pending` / `processing`. The Edit button is disabled outside `.translated`.
- Concurrent batch background processing during an edit session on the same page (the page is finished before edit is enabled, so this is naturally avoided).
- Re-batching adjacent pages on commit. Re-translation is single-page, with preceding pages supplied as read-only context.

## Decisions

### D1: Edit-session state lives on `TranslationViewModel`, scoped by `pageId`

A new private property:

```swift
@MainActor
private var editSession: EditSession?

struct EditSession {
    let pageId: UUID
    var workingBubbles: [BubbleCluster]          // mutable working copy
    var dirtyBubbleIds: Set<UUID>                // UI-only dirty-visual cache for sidebar;
                                                 // NEVER used for OCR classification (see D3).
                                                 // Commit derives OCR-dirty from bbox-vs-snapshot diff.
    var deletedBubbleIds: Set<UUID>              // staged deletions
    var selectedBubbleIds: Set<UUID>             // current selection
    var undoStack: [EditAction]
    var redoStack: [EditAction]
    let originalSnapshot: [TranslatedBubble]     // for Cancel
    let originalPageState: PageState             // always .translated at open; restored on Cancel
}
```

**Why on the view model, not a separate object:**
- Edit state is intrinsically per-page and per-user-session; persistence is not desired (Cancel must work after a crash by simply losing state).
- The view model already mediates between views and services; introducing a parallel `EditCoordinator` adds plumbing without removing complexity.
- All mutations happen on `@MainActor`, so no concurrency primitives are needed.

**Alternatives considered:**
- A separate `@Observable EditCoordinator` injected into views. Rejected: doubles the source of truth for "which page is showing what bubbles" and complicates the binding to `TranslationSidebar`.
- Storing `editSession` per-page inside `MangaPage`. Rejected: encourages multi-page editing, which is an explicit Non-Goal.

### D2: `EditAction` is a sum type; undo replays inverses

```swift
enum EditAction {
    case add(BubbleCluster)
    case delete(BubbleCluster)                       // stages deletion (adds id to deletedBubbleIds)
    case unstageDelete(BubbleCluster)                // reverses a prior staged deletion (removes id from deletedBubbleIds)
    case move(id: UUID, from: CGRect, to: CGRect)
    case resize(id: UUID, from: CGRect, to: CGRect)
    case reorder(from: [UUID], to: [UUID])          // captures full prior order
    case multi([EditAction])                         // for grouped operations (e.g. delete selection of 5)
}
```

Each action knows how to invert itself; `undo()` pops from `undoStack`, applies the inverse, and pushes the original onto `redoStack`. Any new mutation clears `redoStack`.

**Action semantics — apply and inverse:**

| Action | Apply | Inverse on undo |
|---|---|---|
| `.add(b)` | call `ReadingOrderSorter.insertNearestNeighbour(b, into: workingBubbles)` and replace `workingBubbles` with the result (NOT a plain append; new bubble goes immediately after its geometric nearest neighbour, with all `index` values redensified `0..<n`) | remove `b.id` from `workingBubbles` and redensify `index` |
| `.delete(b)` | insert `b.id` into `deletedBubbleIds` (idempotent — set semantics) | remove `b.id` from `deletedBubbleIds` (idempotent) |
| `.unstageDelete(b)` | remove `b.id` from `deletedBubbleIds` (idempotent) | insert `b.id` into `deletedBubbleIds` (idempotent) |
| `.move(id, from, to)` | set bubble's `boundingBox = to`; if `isManual` was false, set to true | set bubble's `boundingBox = from`; **do not** restore `isManual` (sticky per D5) |
| `.resize(id, from, to)` | same as move | same as move |
| `.reorder(from, to)` | reorder `workingBubbles` ids to match `to`; recompute `index` | reorder to match `from`; recompute `index` |
| `.multi(actions)` | apply each in order | inverse each in **reverse** order |

**Un-stage of a deletion is its own first-class action, not a rewrite of history.** Clicking a deletion-marked card pushes a new `.unstageDelete(bubble)` onto the undo stack and clears the redo stack. Any pre-existing `.delete` or `.multi([.delete, ...])` entry remains in the undo stack unchanged. Set-based `deletedBubbleIds` makes every operation idempotent, so undo/redo cycles across the original group delete and a later partial un-stage converge deterministically without "duplicate restore" bugs:

- Worked example: user deletes bubbles `{a, b, c, d, e}` in one shot → undo stack: `[.multi([.delete(a)...delete(e)])]`. User clicks card `c` to un-stage → undo stack: `[.multi(...), .unstageDelete(c)]`, `deletedBubbleIds = {a, b, d, e}`. User presses `Cmd+Z`: pops `.unstageDelete(c)`, applies inverse → `deletedBubbleIds = {a, b, c, d, e}`. Presses `Cmd+Z` again: pops `.multi`, applies inverse → `deletedBubbleIds = {}`. Presses `Cmd+Shift+Z`: re-applies `.multi` → `deletedBubbleIds = {a, b, c, d, e}`. Final-set semantics are preserved at every point because the set is the ground truth and actions are idempotent.

**Why sum type over command pattern with protocols:**
- Exhaustive `switch` keeps the inverse logic in one file; adding a new action type is a compile error in every consumer.
- Value-typed `enum` round-trips trivially through `Array`.

**Stack limits:** none enforced. Each entry is small (UUIDs + two `CGRect`s); 1000 edits is < 100 KB. Realistic sessions are < 50 edits.

### D3: Dirty tracking — three categories

When the user **commits**, every bubble in the final working set (`workingBubbles \ deletedBubbleIds`) is classified along **two independent axes**:

- **OCR axis**: does this bubble need fresh OCR?
- **Translate-input axis**: is this bubble part of the page-level translate call?

**Source of truth for OCR classification is final geometry**, evaluated at commit time. The rule is:

```
isOCRDirty(b) = (b.id ∉ originalSnapshot) || (b.boundingBox != snapshot[b.id].boundingBox)
```

`CGRect` equality is exact (no tolerance). This rule is the **sole** determinant of the OCR axis; `dirtyBubbleIds` is **not** consulted at commit.

| Category | How identified (at commit) | OCR axis | Translate-input axis |
|---|---|---|---|
| **New** | `id ∉ originalSnapshot` | run | included |
| **Geometry-changed** | `id ∈ originalSnapshot` AND current `boundingBox` != snapshot `boundingBox` | run | included |
| **Reorder-or-unchanged geometry** | `id ∈ originalSnapshot` AND current `boundingBox` == snapshot `boundingBox` | skip (reuse snapshot text) | included |
| **Deleted** | `id ∈ deletedBubbleIds` | n/a | excluded |

**Every non-deleted bubble is always part of the translate call**, regardless of dirty status — including the case where the user only reordered or only deleted. The translate-input axis only excludes deletions. The OCR axis is the only one that has a "skip" path; "skip OCR" means the bubble keeps its snapshot `text` and that text is what the translator receives.

**Role of `dirtyBubbleIds` in `EditSession`**: this set is a **UI-side cache** used only for rendering the sidebar's `已修改` dirty visuals during the in-progress session. It is maintained by `applyEditAction` (added on `move`/`resize`) and SHOULD be pruned by undo/redo when the action's effect on `boundingBox` cancels out, but the commit pipeline DOES NOT consult it. Drift between `dirtyBubbleIds` and final geometry affects only UI badges, never OCR cost or correctness.

**Why this rule over membership in `dirtyBubbleIds`**: when the user moves a bubble and then `Cmd+Z`s back to the original position, `boundingBox` is byte-for-byte equal to the snapshot. With a membership-based rule, the bubble would still be OCR-dirty (because `dirtyBubbleIds` recorded the original move), causing an unnecessary OCR round-trip that might produce slightly different text and silently overwrite the user's earlier translation. The geometry-derived rule is deterministic, immune to undo-stack state, and cheap (one `CGRect` compare per bubble).

After OCR returns text for OCR-dirty boxes, the page's bubble set is rebuilt in the user's current order, and a single-page `TranslationService.translate(...)` call runs over the **entire non-deleted set** to give LLM engines full context.

**Why translate the whole page even though only some boxes changed:**
- LLM engines produce more coherent output when given the full page. Translating "the new SFX" alone loses pronoun resolution.
- Cost is bounded (one page), and the user explicitly initiated the action.
- Side benefit: the translator's `detectedTerms` glossary inference sees the full corpus.

### D4: New box reading-order placement — nearest-neighbour insertion

Algorithm:

```
insert(newBox B, into orderedList L):
  if L is empty: append B; return
  let nearest = argmin over b in L of distance(center(B), center(b))
  let i = index of nearest in L
  insert B at position i + 1
```

Distance = Euclidean on box centres in image pixel coordinates.

**Why nearest-neighbour rather than full geometric resort:**
- Once the user has manually reordered, the existing order may reflect story flow rather than geometry. A full re-sort would destroy that intent.
- Nearest-neighbour is monotone: it does not move *any* existing box; the result is always "current order + one new entry".
- Pathological case (new box equidistant from two): tie-break by smaller `(y, x)` of the neighbour's centre. Deterministic, never user-visible as nondeterminism.

**Why "after the neighbour" rather than "before":**
- Manga reading order generally proceeds rightward then downward within a row. A user usually adds a new SFX *adjacent and after* an existing bubble more often than *before*. Empirically tweakable; the user can sidebar-drag if wrong.

Lives in `ReadingOrderSorter` as:

```swift
extension ReadingOrderSorter {
    func insertNearestNeighbour(_ newBox: BubbleCluster, into ordered: [BubbleCluster]) -> [BubbleCluster]
}
```

After insertion, `index` fields on the whole array are recomputed `0..<n` in array order.

### D5: `isManual` flag — single bit, set on first user touch

`BubbleCluster.isManual: Bool = false` (default).

- Set to `true` when the bubble is **created** by the user (drawn).
- Set to `true` when the bubble's geometry is **first modified** by the user (move or resize), regardless of how many subsequent edits occur.
- **Sticky semantics — never set back to `false` by any in-session action**, including `Cmd+Z` undo of the move/resize that first flipped it. The flag records "the user has touched this bubble's geometry at some point", not "the current geometry differs from the auto-detected original". Implementation consequence: the inverse of a `move` / `resize` action only restores `boundingBox`, never `isManual`.
- The flag *can* effectively "reset" only through a session-level **Cancel**, because Cancel restores the entire pre-session snapshot byte-for-byte — including each bubble's `isManual` value as it stood before the session opened. This is restoration of the snapshot, not flag mutation.
- The user-facing Re-translate button preserves manual boxes by skipping OCR detection entirely whenever the page has a committed bubble set. See the MODIFIED `retranslate` requirement: Re-translate's "fresh OCR" branch only fires for pages with no committed bubble set (first translation, post-error reset, post-same-language skip). With a committed set in hand, Re-translate just re-runs the translator over those bubbles — drawn bubbles, edited geometry, and `isManual` flags all survive. This is intentional behaviour, not a future-work item.

Cache JSON: add `"isManual": Bool` with **explicit decoder default of `false`** so old cache rows decode without error.

### D6: Page-switch lock — pure UI disablement, no modal

While `editSession != nil`:
- `ContentView` page navigation buttons → `.disabled(true)`.
- Sidebar thumbnail click handlers → no-op (or grayed out).
- `←` / `→` keyboard shortcuts on the main window → consumed and ignored.
- Window close → blocked at the `@AppKit` window-should-close delegate (the only modal we accept; bypassing this would lose work).

**Why no in-app navigation modal:**
- The user explicitly chose this. Commit and Cancel buttons are always visible in the sidebar header, so the path out is obvious.
- Reduces a class of bugs around dialog focus / dismiss race conditions.

### D7: Sidebar dirty visuals — overlay on `TranslationCard`, not new card type

Within edit mode, `TranslationCard` gains three optional decorations:

- **Pending text** (new box, OCR not run yet): replace `bubble.translatedText` and `bubble.bubble.text` with a localised placeholder `"待處理"` and dim the card.
- **Stale** (geometry-changed): strike through original text, dim translation, append small badge `已修改`.
- **Marked for deletion**: red overlay + strikethrough on entire card; clicking restores (one-step undo for delete).

**Why overlay instead of a separate `EditCard` view:**
- Sidebar order/selection logic stays in one place.
- Round-trip after commit: dirty visuals simply disappear; no view-tree restructuring.

### D8: Drawing gesture composition

Edit mode routes three gesture intents on the image canvas (`ImageViewer`):

1. **Empty-canvas drag** → draw new box. Hit-test: cursor must start outside every existing box's display rect.
2. **Box-body drag** → move existing box. Hit-test: cursor starts inside a box but outside handle zones (16 pt squares at corners / 8 pt strips along edges).
3. **Handle drag** → resize. Hit-test: cursor starts inside a handle zone.

Implemented with one SwiftUI `DragGesture(minimumDistance: 0)` and a small state machine. The first `onChanged` event hit-tests the start point and locks the gesture into exactly one mode: draw, move, or resize. This replaces the earlier three-gesture `.simultaneousGesture(...)` sketch because the unified state machine keeps Esc cancellation and click-vs-drag routing in one place while preserving the same user-visible behaviour. Tap (zero-distance gesture) handles selection (`Shift`/`Cmd` for multi-select).

`Esc` during an in-flight gesture cancels that gesture without committing the action (no `EditAction` recorded).

### D9: Translation context for committed edits — `summariesPreceding(pageIndex:)`

Replace today's rolling-buffer feed with an indexed lookup:

```swift
extension TranslationViewModel {
    /// Returns up to `count` summaries from pages [pageIndex - count ..< pageIndex],
    /// in original page order, joining each page's translated bubbles by " ".
    /// Pages not yet translated are skipped (yielding fewer than `count` summaries).
    func summariesPreceding(pageIndex: Int, count: Int = 3) -> [String]
}
```

`buildTranslationContext` gains a new parameter `precedingPageIndex: Int?`. When `nil` (today's path), it returns the existing rolling-buffer behaviour. When non-nil (edit commit path), it pulls from `summariesPreceding(pageIndex:)`.

**Why not just always use indexed lookup:**
- Out of scope. Today's batch path appends-then-reads in deterministic order, so the buffer = preceding pages by construction. Changing that behaviour would be a separate change with its own risk surface.

### D10: Commit pipeline — sequenced, in-memory-atomic (cache best-effort)

```
commit():
  let s = editSession; precondition(s != nil)
  let workingOrdered = recomputeIndices(s.workingBubbles - s.deletedBubbleIds)

  // Step 0a: final-state no-op short-circuit. If final IDs, order, and geometry
  // equal the session snapshot, only close Edit Mode. Do not commit transient
  // in-session side effects such as a sticky isManual flip from a reverted move.
  if matchesOriginalEditSnapshot(workingOrdered, s.originalSnapshot) {
      page.state = s.originalPageState
      editSession = nil
      return
  }

  // Step 0b: empty-set short-circuit. If the user deleted every bubble, never invoke
  // OCR or the translator (which can fail on missing API key / no network), and
  // skip the .processing transition entirely — there is no async work to wait on.
  if workingOrdered.isEmpty {
      do {
          try cacheService.store(..., bubbles: [])
      } catch {
          // Log a warning through DebugLogger.
      }
      page.state = .translated([])           // direct transition, no .processing
      editSession = nil
      return
  }

  // Non-empty path: enter processing for the duration of OCR + translate.
  enter PageState.processing

  // Step 1: OCR dirty + new — geometry-derived, ignores s.dirtyBubbleIds (UI cache only)
  let snapshotById = Dictionary(uniqueKeysWithValues: s.originalSnapshot.map { ($0.bubble.id, $0.bubble) })
  let toOCR = workingOrdered.filter { b in
      guard let original = snapshotById[b.id] else { return true }            // new
      return b.boundingBox != original.boundingBox                            // geometry-changed
  }
  let ocrResults = try await ocrService.recognize(toOCR, on: page.image)

  // Step 2: assemble full bubble set with merged text
  let merged = workingOrdered.map { bubble in
    if let new = ocrResults[bubble.id] { return bubble.withText(new) }
    else { return bubble }  // reuse existing text
  }

  // Step 3: single-page translate over the full set
  let context = buildTranslationContext(
    usesRecentContext: usesRecentPageContext(engine),
    precedingPageIndex: indexOf(pageId)
  )
  let output = try await translator.translate(bubbles: merged, from: ..., to: ..., context: context)

  // Step 4: try cache store FIRST while we can still roll back
  do {
      try cacheService.store(..., bubbles: output.bubbles)  // throws on disk / sqlite failure
  } catch {
      // Log a warning through DebugLogger.
      // Cache is a best-effort optimization; non-fatal. Continue with the atomic swap.
  }

  // Step 5: atomic swap (UI is the source of truth, not the cache)
  page.state = .translated(output.bubbles)
  editSession = nil
```

**Atomicity scope explicitly excludes cache persistence.** The transactional commit covers OCR → translate → in-memory swap of `PageState` and `editSession`. `CacheService.store` is a best-effort optimization (a read-through cache that speeds up re-opening the same image later); its failure SHALL be logged at warning level and SHALL NOT affect the user-visible commit. Rationale: (a) the in-memory `PageState` is the source of truth for the running session — rolling it back to `.error` because SQLite is unavailable would punish the user for a problem outside their control; (b) failing the commit would force the user to re-do all edits or retry; (c) cache loss only affects performance on the next open of the same image, not correctness. Any thrown error from OCR or `TranslationService.translate(...)` (Steps 1-3) → `PageState.error(...)`; `editSession` is **kept open** so the user can retry or cancel. The page enters `.error` while the session holds `originalPageState == .translated`. If the user then cancels, `cancelEditSession()` restores both `workingBubbles → originalSnapshot` **and** `page.state → originalPageState` (i.e. `.translated`), clearing the error. Without this rule, a transient API failure followed by Cancel would silently leave the page stuck in `.error`, defeating the user's expectation that Cancel is a clean escape hatch.

**Why keep session open on error:**
- The user has invested edit time; throwing it away on a transient network failure is hostile.
- The view-model already distinguishes `.error` from `.translated`, and the edit UI can show the error inline.

### D11: Cache backward compatibility

`CacheService.swift` JSON encoding (lines around 388-407):
- Encoder: add `"isManual"` key always.
- Decoder: `let isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false`.

No version bump on the cache schema. Old rows produce `isManual: false` for every bubble, which is the correct historical value (no manual edits existed before this change).

## Risks / Trade-offs

- **[SwiftUI gesture conflicts]** Drag-to-draw vs. drag-existing-box vs. tap-to-select are notoriously tricky in SwiftUI. → **Mitigation**: hit-test in `onChanged` first event and short-circuit; integration-test by running the app and exercising every combination manually before declaring done; encapsulate gesture composition in a single `EditCanvas` view with no external state-bleed.
- **[Nearest-neighbour heuristic surprises user]** A new box might land in an unexpected sidebar slot. → **Mitigation**: drag-to-reorder in sidebar is one gesture away; design.md documents the heuristic explicitly so future maintainers do not "fix" it; nearest-neighbour is unit-tested with documented expectations.
- **[Cache size growth from `isManual`]** Negligible (~5 bytes per bubble). No mitigation needed.
- **[LLM re-translation cost on every commit]** A page-edit cycle costs one full-page LLM call. → **Mitigation**: that is precisely the user's intent when pressing Done; the existing per-page Re-translate button already exposes this cost.
- **[Concurrent batch background work mutating the page being edited]** Cannot happen: Edit button is gated on `PageState.translated`, and once edit opens, the page state is captured into the working copy. Background batch operates on other pages or is already finished for this page.
- **[Undo through `Reorder` action with `from`/`to` of UUID lists]** Diff-based reorder is replaced by full-list snapshot in the action — simpler and immune to intervening edits within the same session. Memory cost is bounded by bubble count.
- **[`isManual` semantics drift]** Future "re-detect this page" flow must decide what to do with `isManual == true` boxes. → **Mitigation**: a comment in `Models.swift` next to the field documents the meaning and the open future-work decision; no behaviour is committed today.
- **[Page-switch lock feels like a trap to a user who forgot they were editing]** → **Mitigation**: sidebar header is sticky and always shows Done / Cancel buttons; the empty disabled state of nav controls is itself a hint.
