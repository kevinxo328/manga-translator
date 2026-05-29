## ADDED Requirements

### Requirement: Indexed preceding-page summary lookup for Edit Mode Commit

The system SHALL expose a helper `summariesPreceding(pageIndex: Int, count: Int = 3) -> [String]` on `TranslationViewModel` that returns up to `count` page summaries drawn from pages whose page index is strictly less than `pageIndex`.

The helper SHALL:

- Iterate pages by ascending page index from `0..<pageIndex`.
- Include a page if and only if that page's current `PageState` is `.translated`.
- For each included page, compute its summary as the concatenation of `TranslatedBubble.translatedText` ordered by `TranslatedBubble.index`, joined by a single space character.
- Return the **last `count`** included summaries in ascending page-index order. If fewer than `count` pages qualify, return all qualifying summaries.

The helper SHALL be a pure read over current page state and SHALL NOT mutate the rolling recent-context window used by initial or batch translation.

For an Edit Mode Commit on page N with a context-consuming LLM engine, the system SHALL call `summariesPreceding(pageIndex: N, count: 3)` and pass the result as `TranslationContext.recentPageSummaries` to `TranslationService.translate(...)`. The system SHALL NOT consume the rolling window on this code path.

For an Edit Mode Commit with a non-context engine (DeepL, Google), `recentPageSummaries` SHALL be empty.

After a successful Edit Mode Commit, the system SHALL NOT append the committed page's summary to the rolling recent-context window. The rolling window is reserved for initial/batch translation flows.

#### Scenario: summariesPreceding returns up to count entries
- **WHEN** pages 0, 1, 2, 3, 4 are all `.translated` and the user commits an edit on page 5
- **THEN** `summariesPreceding(pageIndex: 5, count: 3)` returns three entries for pages 2, 3, 4 in that order

#### Scenario: summariesPreceding skips non-translated pages
- **WHEN** page 0 is `.translated`, page 1 is `.error`, page 2 is `.translated`, page 3 is `.pending`, page 4 is `.translated`
- **AND** the user commits an edit on page 5
- **THEN** `summariesPreceding(pageIndex: 5, count: 3)` returns three entries for pages 0, 2, 4 in that order

#### Scenario: summariesPreceding returns empty for first page
- **WHEN** the user commits an edit on page 0
- **THEN** `summariesPreceding(pageIndex: 0)` returns an empty array

#### Scenario: Commit does not pollute the rolling window
- **WHEN** the rolling window before an Edit Mode Commit contains summaries for pages [17, 18, 19]
- **AND** the user commits an edit on page 5
- **THEN** after Commit completes, the rolling window still contains summaries for pages [17, 18, 19]
- **AND** page 5's new summary is NOT appended to the rolling window

#### Scenario: Edit Commit uses summariesPreceding, not the rolling window
- **WHEN** the user commits an edit on page 5 with an OpenAI Compatible engine
- **AND** the rolling window currently contains pages [17, 18, 19]
- **AND** pages 2, 3, 4 are `.translated`
- **THEN** the `TranslationContext.recentPageSummaries` passed to the translator equals `summariesPreceding(pageIndex: 5, count: 3)` (pages 2, 3, 4)
- **AND** does not equal the rolling window contents

#### Scenario: Edit Commit with non-context engine has empty summaries
- **WHEN** the user commits an edit on page 5 with DeepL
- **THEN** `recentPageSummaries` passed to the translator is empty
