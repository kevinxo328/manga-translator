## ADDED Requirements

### Requirement: Edit-mode Commit reuses the per-page translation entry point

An Edit Mode Commit (see `manual-bubble-editing`) SHALL drive translation through the same per-page entry point used by the user-facing Re-translate button — `TranslationService.translate(bubbles:from:to:context:)` for the single page being committed.

The Edit Mode Commit path SHALL differ from the Re-translate button path in these ways:

- OCR is run only on bubbles classified as OCR-dirty (newly added or geometry-changed), not over the whole image. Bubbles classified as OCR-clean reuse their pre-existing `text`. The Re-translate button continues to run OCR over the whole image.
- The `TranslationContext.recentPageSummaries` is sourced from `summariesPreceding(pageIndex:)` (the indexed lookup), not from the rolling recent-context window.
- The Edit Mode Commit path supports an **empty-set short-circuit** (see `manual-bubble-editing`): when the user has deleted every bubble, the path terminates immediately at `.translated([])` without invoking OCR, the translator, or transitioning through `.processing`. The Re-translate button has no equivalent short-circuit — it always runs full-image OCR.

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

#### Scenario: Re-translate button still runs full-image OCR
- **WHEN** the user presses the Re-translate button (no Edit Mode session active)
- **THEN** the OCR step re-detects and re-recognizes text from the whole page image
- **AND** the behaviour is identical to today's Re-translate behaviour

#### Scenario: Edit Commit empty-set path skips .processing
- **WHEN** the user deletes every bubble in Edit Mode and presses Done
- **THEN** the page transitions directly from `.translated(...)` to `.translated([])`
- **AND** the page never enters `.processing` during this Commit
- **AND** no progress spinner is shown
