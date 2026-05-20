## Purpose

Rolling context window that feeds recent translated page content into LLM prompts, enabling more coherent and consistent translations across consecutive manga pages.
## Requirements
### Requirement: Rolling recent-page context window
The system SHALL maintain an in-memory rolling window of the last 3 successfully translated pages' text for context-consuming LLM translation engines. Each page summary SHALL concatenate that page's translated bubble text ordered by `TranslatedBubble.index`. The window SHALL be session-only and cleared when the app is restarted or a new image set is loaded.

For batch operations, the rolling window SHALL be derived from page index order, not asynchronous completion order. For page N, the context window SHALL include only successful pages whose page index is lower than N, keeping at most the most recent 3 such page summaries in ascending page-index order.

Pages that fail during image loading, OCR, cache lookup, translation, or cache storage SHALL NOT contribute to the rolling context window. Later pages SHALL continue when their own prerequisites succeed. A page whose final translated result comes from the translation cache is a successful translated page for rolling-context purposes and SHALL contribute its cached translated text to later LLM pages without re-running OCR or translation.

#### Scenario: Context window accumulates across pages
- **WHEN** user translates pages 1, 2, and 3 in sequence
- **THEN** translating page 4 includes a summary of pages 1–3 in the LLM prompt

#### Scenario: Context window drops oldest page
- **WHEN** user has translated 4 or more pages
- **THEN** only the most recent 3 pages are included in the context window

#### Scenario: Context clears on new image set
- **WHEN** user opens a different folder or file
- **THEN** the rolling context window is reset to empty

#### Scenario: Batch context follows page order, not completion order
- **WHEN** user batch-translates pages 1, 2, 3, and 4 with a context-consuming LLM engine
- **AND** asynchronous OCR or translation work completes in an order different from page index order
- **THEN** page 3 receives recent-page summaries for pages 1 and 2 in page-index order
- **AND** page 4 receives recent-page summaries for pages 1, 2, and 3 in page-index order
- **AND** no page receives summaries from a later page

#### Scenario: Cache-hit page contributes to later LLM context
- **WHEN** user batch-translates page 1 and page 2 with a context-consuming LLM engine
- **AND** page 1 has a valid translation-cache hit for the active image hash, source language, target language, and engine
- **THEN** the system uses page 1's cached translated bubbles without calling OCR or the translation service for page 1
- **AND** page 2 receives a recent-page summary built from page 1's cached translated bubbles ordered by reading index

#### Scenario: Failed page is skipped by later LLM context
- **WHEN** user batch-translates page 1 and page 2 with a context-consuming LLM engine
- **AND** page 1 fails during image loading, OCR, cache lookup, translation, or cache storage
- **AND** page 2 can be translated successfully
- **THEN** page 1 contributes no recent-page summary
- **AND** page 2 still translates successfully
- **AND** page 2's recent-page summaries exclude page 1

#### Scenario: Batch re-translate uses page-ordered context
- **WHEN** user re-translates all pages with a context-consuming LLM engine
- **THEN** the system bypasses translation-cache lookup for each page
- **AND** the recent-page summaries used during re-translation follow the same page-index ordering rules as initial batch translation
- **AND** each successful re-translated page contributes its new translated text to later pages in that same re-translate-all operation

### Requirement: Recent context injected into LLM prompt
The system SHALL include the rolling context window in the LLM system prompt when context is available. The context SHALL be presented as a brief per-page summary under a "## Recent context" section. Only context-consuming LLM engines SHALL receive recent-page context injection. The context-consuming LLM engines are OpenAI Compatible and GitHub Copilot.

DeepL and Google Translate SHALL NOT receive recent-page summaries and SHALL NOT read from or write to the rolling recent-page context window. This restriction applies to both single-page translation and batch translation. DeepL and Google Translate SHALL still receive active glossary terms through `TranslationContext.glossaryTerms` when an active glossary exists.

#### Scenario: LLM receives prior page context
- **WHEN** user translates a page and prior translated pages exist in the window
- **THEN** the LLM system prompt includes those pages' translations under "## Recent context (previous pages)"

#### Scenario: First page translation has no context
- **WHEN** user translates the first page of a session
- **THEN** no "## Recent context" section is included in the prompt

#### Scenario: DeepL and Google do not receive recent-page summaries
- **WHEN** user translates multiple pages with DeepL or Google Translate
- **THEN** each translation request has an empty `recentPageSummaries` array
- **AND** those pages do not add summaries to the rolling recent-page context window

#### Scenario: Non-LLM engines still receive glossary terms
- **WHEN** user translates a page with DeepL or Google Translate
- **AND** an active glossary is selected
- **THEN** the translation request includes the active glossary terms
- **AND** the translation request has an empty `recentPageSummaries` array

