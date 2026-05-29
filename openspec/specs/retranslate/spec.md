## Purpose

Re-translate the current page by performing a full OCR + translation pipeline with current settings, bypassing cache lookup.
## Requirements
### Requirement: Re-translate current page with fresh OCR
The system SHALL provide a re-translate action that re-runs translation on the current page using the current engine and language settings, bypassing cache lookup.

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
- **WHEN** the user has committed manual edits on a page, then changes the translation engine in the toolbar and presses Re-translate (or the engine-change auto-triggers re-translate)
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

### Requirement: Re-translate button in translation sidebar
The system SHALL display a re-translate button in the TranslationSidebar header area. The button SHALL always be visible when a page is loaded.

#### Scenario: Button visibility
- **WHEN** a page is loaded (any state)
- **THEN** the re-translate button is visible in the sidebar header

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

