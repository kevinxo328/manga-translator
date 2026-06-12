## Purpose

Re-translate the current page by performing a full OCR + translation pipeline with current settings, bypassing cache lookup.
## Requirements
### Requirement: Re-translate current page with fresh OCR
The system SHALL provide a re-translate action that re-runs translation on the current page using the current engine and language settings, bypassing cache lookup. The bypass-cache semantics of this requirement apply only to the explicit re-translate actions — the sidebar Re-translate button and the toolbar Re-translate All button. Changing the translation engine SHALL NOT route through this action; engine changes are governed by the `Engine switch reuses per-engine cache` requirement.

**Bubble-set preservation rule**: when the page's current state is `.translated` with a non-empty bubble set, the Re-translate action SHALL reuse that committed bubble set verbatim — preserving every bubble's `boundingBox`, `text` (OCR result), `index` (reading order), `isInverted`, and `isManual` flag. The OCR detection pass SHALL NOT run on this code path. Only the translation step re-runs, so the user's committed edits (drawn bubbles, moved/resized bubbles, reordered sequences, `isManual=true` flags) survive every subsequent Re-translate.

When the page's current state is NOT `.translated` (i.e. the page has no committed bubble set — first translation, after an error reset, or after a same-language skip), the Re-translate action SHALL fall back to the original full pipeline: run OCR detection over the whole image, then translate the detected bubbles. This preserves the first-time translation path while protecting users who have invested editing effort.

The complete results SHALL be written back to cache, overwriting any existing entry, regardless of which branch fired.

#### Scenario: Re-translate preserves committed bubbles including isManual
- **WHEN** the user has translated a page (auto-detect produced 5 bubbles), then entered Edit Mode and drew a 6th bubble (`isManual=true`) and resized one of the auto bubbles (`isManual` flips to `true`), then committed
- **AND** the user presses Re-translate (with no Edit Mode session active)
- **THEN** the system SHALL NOT invoke `OCRRouter.processPage(...)` for this page
- **AND** the translator receives the same 6 bubbles in the same order with their `boundingBox`, `text`, and `isManual` values unchanged
- **AND** the resulting cache entry SHALL contain those same 6 bubbles with `isManual=true` for the drawn bubble and for the resized one

#### Scenario: Re-translate with different engine preserves edits
- **WHEN** the user has committed manual edits on a page, then changes the translation engine in the toolbar, lets the engine-switch handling complete (see `Engine switch reuses per-engine cache`), and then presses Re-translate
- **THEN** the bubble set is preserved verbatim
- **AND** the new engine receives those bubbles for translation
- **AND** the cache key for the new engine is overwritten with the translated result

#### Scenario: Re-translate first-time falls back to full OCR
- **WHEN** the user opens a fresh image whose page state is `.pending` (no committed bubble set yet) and the cache is empty
- **THEN** Re-translate (or the implicit initial translation) SHALL run the full OCR detection pass over the image
- **AND** the resulting bubbles SHALL all have `isManual=false`

#### Scenario: Re-translate after error reset falls back to full OCR
- **WHEN** a previous translation attempt failed and the user dismissed the error so the page state is `.pending`
- **AND** the user presses Re-translate
- **THEN** the system SHALL run the full OCR detection pass (no committed bubble set exists to preserve)

#### Scenario: Re-translate while no translations exist
- **WHEN** user views a page that is `.processing` or `.error`
- **THEN** the re-translate button SHALL be disabled or hidden

#### Scenario: Error during re-translate preserves bubbles for retry
- **WHEN** re-translation fails (e.g., network error)
- **THEN** the system SHALL surface the error and SHALL restore the previous `.translated` state (committed bubbles and `isManual` flags intact) so the user does not lose their committed work

### Requirement: Engine switch reuses per-engine cache
When the user changes the translation engine while a page is loaded, the system SHALL NOT bypass the cache unconditionally. The engine switch SHALL be handled as follows.

While translation is in flight (batch translation running, or any page in `.processing` from a single-page flow), the per-page engine-switch flow SHALL NOT execute: the toolbar engine picker is disabled (see `batch-processing` — Pipeline-affecting controls locked while translation is in flight), and the engine-switch handler SHALL ignore engine preference changes that originate elsewhere (e.g. the Settings window) until no translation remains in flight. The preference value itself still updates, so subsequent translations use the new engine; only the immediate per-page switch is suppressed.

When the current page's state is `.translated` with a non-empty committed bubble set, the system SHALL look up the new engine's cache entry and compare its bubble layout against the committed set. The layouts match when both contain the same number of bubbles and, comparing both sequences sorted by `index`, every pair has an equal `boundingBox` (exact equality, no tolerance), equal source `text`, and equal `index`. Translated text SHALL be excluded from the comparison.

- On a cache hit with matching layout, the system SHALL display the cached result without invoking OCR detection, without calling the translation service, and without writing to the cache.
- On a cache miss, or on a cache hit whose layout does not match the committed set, the system SHALL preserve the committed bubble set verbatim (per the bubble-set preservation rule of `Re-translate current page with fresh OCR`), SHALL NOT run OCR detection, SHALL re-run only the translation step with the new engine, and SHALL overwrite the new engine's cache entry on success.

When the current page has no committed non-empty bubble set (never translated, error reset, or emptied via Edit Mode), the engine switch SHALL behave as the standard translation path: cache lookup first, full OCR pipeline on a miss.

If translation fails during an engine switch, the system SHALL restore the page's previous `.translated` state (committed bubbles and `isManual` flags intact), matching the error behavior of the explicit Re-translate action.

#### Scenario: Engine switch hits matching cache without API call
- **WHEN** the user translated a page with engine A, then with engine B, made no edits, and switches the toolbar engine back to A
- **THEN** the system SHALL NOT invoke `OCRRouter.processPage(...)` and SHALL NOT call the translation service
- **AND** the page displays engine A's cached translations
- **AND** no cache write occurs

#### Scenario: Engine switch with cache miss preserves bubbles and translates only
- **WHEN** the user translated a page with engine A (no manual edits) and switches to engine B, which has no cache entry for this page
- **THEN** the system SHALL NOT invoke `OCRRouter.processPage(...)`
- **AND** engine B receives the committed bubbles verbatim (same `boundingBox`, `text`, `index`) for translation
- **AND** the result is written to engine B's cache entry

#### Scenario: Engine switch after manual edits ignores stale cache
- **WHEN** the user translated a page with engine A, then with engine B, then committed an Edit Mode session that drew a new bubble (`isManual=true`), and switches back to engine A
- **THEN** engine A's stale cache entry (whose layout lacks the drawn bubble) SHALL NOT be used
- **AND** the committed bubble set including the drawn bubble is preserved and re-translated by engine A
- **AND** engine A's cache entry is overwritten with the edited layout

#### Scenario: Engine switch after reorder-only edit ignores stale cache
- **WHEN** the user translated a page with engines A and B, then committed an Edit Mode session that only reordered bubbles (no geometry change, so no `isManual` flag flips), and switches back to engine A
- **THEN** engine A's stale cache entry (whose `index` values predate the reorder) SHALL NOT be used
- **AND** the committed bubble set with the user's reading order is preserved and re-translated by engine A

#### Scenario: Engine switch on an untranslated page follows the standard path
- **WHEN** the user switches the engine while the current page is `.pending` with no committed bubble set
- **THEN** the system looks up the new engine's cache and, on a miss, runs the full OCR detection pass before translating

#### Scenario: Translation failure during engine switch restores previous state
- **WHEN** an engine switch requires re-translation (cache miss) and the translation service fails
- **THEN** the system SHALL surface the error and restore the previous `.translated` state with committed bubbles and `isManual` flags intact

#### Scenario: Engine preference change while translation is in flight is not processed per-page
- **WHEN** batch translation is running, or any page is in `.processing` from a single-page flow, and `preferences.translationEngine` changes (e.g. via the Settings window)
- **THEN** `switchEngineForCurrentPage()` SHALL return without mutating any page state, calling OCR, the translation service, or the cache
- **AND** translations started after the in-flight work finishes use the new engine

### Requirement: Re-translate button in translation sidebar
The system SHALL display a re-translate button in the TranslationSidebar header area. The button SHALL always be visible when a page is loaded. The button SHALL be disabled while batch translation is running, regardless of the current page's own state (see `batch-processing` — Pipeline-affecting controls locked while translation is in flight).

#### Scenario: Button visibility
- **WHEN** a page is loaded (any state)
- **THEN** the re-translate button is visible in the sidebar header

#### Scenario: Button disabled during batch translation
- **WHEN** batch translation is running and the current page has already reached `.translated`
- **THEN** the re-translate button is visible but disabled
- **AND** it re-enables when the batch finishes

### Requirement: Loading state during re-translation
The system SHALL indicate a loading state while re-translation is in progress. The page state SHALL transition to processing and back to translated upon completion.

#### Scenario: Loading indicator during re-translate
- **WHEN** user triggers re-translate
- **THEN** the UI shows a processing state until the new translation completes

#### Scenario: Error during re-translate
- **WHEN** re-translation fails (e.g., API error)
- **THEN** the system SHALL display the error and preserve the previous translation results

### Requirement: Edit-mode Commit reuses the per-page translation entry point

An Edit Mode Commit (see `manual-bubble-editing`) SHALL drive translation through the same per-page entry point used by the user-facing Re-translate button — `TranslationService.translate(bubbles:from:to:context:)` for the single page being committed.

The Edit Mode Commit path SHALL differ from the Re-translate button path in these ways:

- The Edit Mode Commit path runs OCR only on bubbles classified as OCR-dirty (newly added or geometry-changed). Bubbles classified as OCR-clean reuse their pre-existing `text`. The Re-translate button path runs OCR only when no committed bubble set exists for the page (see the MODIFIED `Re-translate current page` requirement below).
- The `TranslationContext.recentPageSummaries` is sourced from `summariesPreceding(pageIndex:)` (the indexed lookup), not from the rolling recent-context window.
- The Edit Mode Commit path supports an **empty-set short-circuit** (see `manual-bubble-editing`): when the user has deleted every bubble, the path terminates immediately at `.translated([])` without invoking OCR, the translator, or transitioning through `.processing`.

Both paths SHALL share the same cache-write semantics on the non-empty path: on success, the page's cache entry is overwritten with the new `[TranslatedBubble]` (best-effort; cache failure is logged via `DebugLogger` and SHALL NOT roll back the in-memory commit, per `manual-bubble-editing` Commit requirement).

Both paths SHALL share the same processing-state semantics on the non-empty path: the page transitions to `.processing` for the duration of the OCR + translator work and to `.translated` or `.error` on completion. The empty-set Edit Mode Commit path SHALL NOT enter `.processing`.

Neither path SHALL invoke the multi-page LLM batch grouping.

#### Scenario: Edit Commit and Re-translate share the per-page translator call
- **WHEN** the user commits an edit on page 5 with the OpenAI Compatible engine
- **THEN** the system invokes `TranslationService.translate(...)` once for page 5
- **AND** the system does not invoke `TranslationService.translateBatch(...)`

#### Scenario: Edit Commit skips OCR for clean bubbles
- **WHEN** the user commits an edit on page 5 where 1 box is newly drawn, 1 box was moved, and 6 boxes are unchanged
- **THEN** OCR runs on exactly 2 bubbles
- **AND** the remaining 6 bubbles' text values come from the original snapshot
- **AND** the translator receives all 8 bubbles in the user's final order

#### Scenario: Edit Commit empty-set path skips .processing
- **WHEN** the user deletes every bubble in Edit Mode and presses Done
- **THEN** the page transitions directly from `.translated(...)` to `.translated([])`
- **AND** the page never enters `.processing` during this Commit
- **AND** no progress spinner is shown

