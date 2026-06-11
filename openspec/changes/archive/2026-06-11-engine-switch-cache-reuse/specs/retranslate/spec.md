## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Engine switch reuses per-engine cache
When the user changes the translation engine while a page is loaded, the system SHALL NOT bypass the cache unconditionally. The engine switch SHALL be handled as follows.

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
