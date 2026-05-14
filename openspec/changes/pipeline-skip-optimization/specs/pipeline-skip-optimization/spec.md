## ADDED Requirements

### Requirement: Skip OCR when source and target language are identical
The system SHALL bypass OCR and translation entirely when `sourceLanguage == targetLanguage`. The page state SHALL be set to `.translated([])` without running any OCR engine or translation service. No cache write SHALL occur for this bypass.

#### Scenario: Same-language page produces empty translated state immediately
- **WHEN** `translatePage(at:)` is called and `preferences.sourceLanguage == preferences.targetLanguage`
- **THEN** OCR is not invoked, translation is not invoked, and the page state is `.translated([])`

#### Scenario: Same-language bypass is logged with metadata
- **WHEN** `translatePage(at:)` is called and source equals target language
- **THEN** a log entry with level `.info` and category `.pipeline` is emitted whose `metadata` SHALL include `reason` with value `"same_language"`, `source_language`, `target_language`, and `page_index`

### Requirement: Filter meaningless bubbles before translation and sidebar
The system SHALL discard any OCR result bubble whose text is empty or consists entirely of punctuation and whitespace characters. Discarded bubbles SHALL NOT be passed to the translation engine and SHALL NOT appear as entries in the sidebar.

#### Scenario: All-punctuation bubble is not translated and not shown in sidebar
- **WHEN** OCR returns a bubble whose `text` property contains only punctuation or whitespace (e.g. `"。"`, `"—"`, `"  "`)
- **THEN** that bubble is excluded from the translation request and does not appear in the page's `.translated([...])` array

#### Scenario: Empty-text bubble is not translated and not shown in sidebar
- **WHEN** OCR returns a bubble whose `text` property is the empty string `""`
- **THEN** that bubble is excluded from the translation request and does not appear in the page's `.translated([...])` array

#### Scenario: Page with only meaningless bubbles produces empty translated state
- **WHEN** all OCR results on a page are empty or punctuation-only
- **THEN** the page state is `.translated([])` and translation is not invoked

#### Scenario: Mixed page: only meaningful bubbles reach translation and sidebar
- **WHEN** OCR returns a mix of meaningful and punctuation-only bubbles
- **THEN** only the meaningful bubbles are passed to the translation engine and appear in the sidebar

### Requirement: Log meaningless-bubble filter decisions with structured metadata
The system SHALL emit a log entry when one or more OCR result bubbles are discarded as meaningless, and a separate log entry when all bubbles are discarded and translation is skipped entirely. Both entries SHALL use category `.pipeline` and level `.info`. Both entries SHALL include a `metadata` dictionary with machine-readable fields.

#### Scenario: Filtered bubble count is logged with metadata
- **WHEN** N > 0 OCR bubbles are discarded as meaningless out of M total
- **THEN** a log entry with category `.pipeline` is emitted whose `metadata` SHALL include `filtered_count` (value: N as a string), `total_count` (value: M as a string), and `page_index`

#### Scenario: Full skip is logged with metadata when no meaningful bubbles remain
- **WHEN** all OCR bubbles are discarded and translation is not invoked
- **THEN** a log entry with category `.pipeline` is emitted whose `metadata` SHALL include `reason` with value `"all_bubbles_meaningless"` and `page_index`
