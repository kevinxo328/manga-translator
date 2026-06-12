## MODIFIED Requirements

### Requirement: Re-translate button in translation sidebar
The system SHALL display a re-translate button in the TranslationSidebar header area. The button SHALL always be visible when a page is loaded. The button SHALL be disabled while batch translation is running, regardless of the current page's own state (see `batch-processing` — Pipeline-affecting controls locked while translation is in flight).

#### Scenario: Button visibility
- **WHEN** a page is loaded (any state)
- **THEN** the re-translate button is visible in the sidebar header

#### Scenario: Button disabled during batch translation
- **WHEN** batch translation is running and the current page has already reached `.translated`
- **THEN** the re-translate button is visible but disabled
- **AND** it re-enables when the batch finishes

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
