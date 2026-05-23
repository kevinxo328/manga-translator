## MODIFIED Requirements

### Requirement: Rolling recent-page context window
The system SHALL maintain an in-memory rolling window of the last 3 successfully translated pages' text for context-consuming LLM translation engines. Each page summary SHALL concatenate that page's translated bubble text ordered by `TranslatedBubble.index`. The window SHALL be session-only and cleared when the app is restarted or a new image set is loaded.

For batch operations, the rolling window SHALL be derived from page index order, not asynchronous completion order.

For a per-page translation request that targets page N, the context window SHALL include only successful pages whose page index is lower than N, keeping at most the most recent 3 such page summaries in ascending page-index order.

For a multi-page LLM batch request containing pages F through L (inclusive, with F ≤ L), the context window passed to the LLM as the batch-level recent-context summary SHALL include only successful pages whose page index is lower than F, keeping at most the most recent 3 such page summaries in ascending page-index order. The system SHALL NOT inject an explicit recent-context summary for pages F+1 through L; within the batch, page-to-page context is carried implicitly by the LLM's own prior output appearing earlier in the same response.

After a multi-page batch successfully completes, the system SHALL append each translated page in the batch to the rolling window in ascending page-index order, then trim the window to the most recent 3 entries. The rolling window is observed only at the start of the next batch or per-page request, not during the in-flight LLM call.

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
- **THEN** page 3 receives recent-page summaries that include at most pages 1 and 2 (the pages whose index is strictly lower than 3 within this batch run) in page-index order
- **AND** page 4 receives recent-page summaries that include at most pages 1, 2, and 3 in page-index order
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

#### Scenario: Multi-page batch boundary samples rolling window before the first page in the batch
- **WHEN** user batch-translates pages 1 through 6 with a context-consuming LLM engine
- **AND** the multi-page batch scheduler groups pages 1, 2, 3 into one LLM request and pages 4, 5, 6 into a second LLM request
- **THEN** the first batch's LLM prompt contains no `## Recent context` section because no successful page has index lower than 1
- **AND** the second batch's LLM prompt contains a `## Recent context` section listing pages 1, 2, 3 in ascending page-index order
- **AND** neither batch's prompt contains explicit recent-context summaries for pages internal to that same batch

#### Scenario: Within-batch context is implicit in the same LLM response
- **WHEN** user batch-translates pages 4, 5, 6 in a single LLM request after pages 1, 2, 3 already translated successfully
- **THEN** the batch's `## Recent context` section lists pages 1, 2, 3 only
- **AND** page 5's translation is generated after page 4's translation in the same LLM response without an additional `## Recent context (page 4)` block in the user prompt
- **AND** page 6's translation is generated after pages 4 and 5 in the same response without an additional `## Recent context (pages 4, 5)` block

#### Scenario: Cache hit ends the current batch and contributes to later batches
- **WHEN** user batch-translates pages 1 through 5 with a context-consuming LLM engine
- **AND** page 3 has a valid translation-cache hit, pages 1, 2, 4, 5 are misses
- **THEN** the batch scheduler issues at most two LLM batch requests: one containing pages 1 and 2, and one containing pages 4 and 5
- **AND** the second batch's `## Recent context` section is sampled from pages whose index is lower than 4, including page 3's cached translated bubbles in ascending page-index order
- **AND** page 3 itself is never sent in an LLM batch request

#### Scenario: Batch failure fallback preserves per-page serial context invariants
- **WHEN** user batch-translates pages 1 through 5 with a context-consuming LLM engine
- **AND** the batch request grouping pages 3, 4, 5 fails twice (one initial attempt plus one retry)
- **THEN** the system finalizes pages 3, 4, and 5 by calling the per-page translation service in page-index order
- **AND** fallback uses the same rolling-window update rules as today's per-page serial finalize loop
- **AND** page 4's per-page request sees pages 1, 2, and 3 in `## Recent context` after page 3 finishes
- **AND** page 5's per-page request sees pages 2, 3, 4 in `## Recent context` after page 4 finishes

#### Scenario: Cancel during a batch returns the batch's pages to pending without polluting the window
- **WHEN** a batch request grouping pages 2, 3, 4 is in flight
- **AND** the user cancels the batch translation run
- **THEN** pages 2, 3, and 4 return to the `.pending` state
- **AND** no recent-page summary for pages 2, 3, or 4 is appended to the rolling window
- **AND** later batches that have not yet started do not start
- **AND** any page that was already translated before the cancel (cache-hit pages, prior batches' successful pages, prior batches' fallback-route successes) keeps its final state and its rolling-window contribution

### Requirement: Recent context injected into LLM prompt
The system SHALL include the rolling context window in the LLM system prompt when context is available. The context SHALL be presented as a brief per-page summary under a "## Recent context" section. Only context-consuming LLM engines SHALL receive recent-page context injection. The context-consuming LLM engines are OpenAI Compatible and GitHub Copilot.

For a per-page LLM request that targets page N, the `## Recent context` section SHALL summarize the rolling window observed immediately before the request, which contains pages whose index is lower than N according to the rolling window requirement.

For a multi-page LLM batch request that contains pages F through L, the `## Recent context` section SHALL appear at most once in the system prompt and SHALL summarize the rolling window observed immediately before the batch, which contains pages whose index is lower than F. The user prompt SHALL list the requested pages F through L in ascending page-index order, each page identified by a stable page identifier in both request and response. The batch prompt SHALL use a dedicated multi-page JSON contract whose response root object is `{"pages":[...]}` and whose page objects contain `page_id`, `bubbles`, and optional `detected_terms`. The system SHALL NOT include any additional `## Recent context` block describing pages F through L themselves inside the same batch's user prompt.

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

#### Scenario: Multi-page batch prompt has one recent-context block and ordered pages
- **WHEN** the system issues a multi-page LLM batch request for pages 4, 5, 6 with rolling window containing pages 1, 2, 3
- **THEN** the system prompt contains exactly one `## Recent context` section summarizing pages 1, 2, 3 in ascending page-index order
- **AND** the user prompt lists the requested pages in the order 4, 5, 6
- **AND** each requested page is identified by a stable identifier that the response parser uses to map translated output back to the source page
- **AND** the user prompt contains no `## Recent context` block for pages 4, 5, or 6

## ADDED Requirements

### Requirement: Multi-page LLM batch grouping
The system SHALL group consecutive miss pages into multi-page LLM batch requests when batch translation runs with a context-consuming LLM engine (GitHub Copilot or OpenAI Compatible).

A batch group is formed by appending consecutive pages whose preparation produced fresh OCR results (not a translation-cache hit) while both of the following invariants hold:

- The sum of bubble counts across all pages in the group, including the next candidate, is at most 45.
- The number of pages in the group, including the next candidate, is at most 5.

The system SHALL flush the current group and start a new group when any of the following occurs:

- Appending the next page would break either invariant.
- The next prepared page is a translation-cache hit. Cache-hit pages SHALL NOT enter any batch group.
- The page list is exhausted.

A single page whose bubble count exceeds 45 SHALL form a batch group of exactly one page; the system SHALL NOT split such a page across multiple groups.

Per-page translation entry points (single-page retranslate via `translatePage(at:bypassCache:)`) SHALL NOT use the multi-page batch grouping path. They SHALL continue to call the per-page translation service method directly.

DeepL and Google Translate SHALL NOT use the multi-page batch grouping path. Their existing per-page parallel pipeline is unchanged.

#### Scenario: Five consecutive miss pages with low bubble counts form one batch
- **WHEN** user batch-translates pages 1 through 5 with a context-consuming LLM engine
- **AND** each page is a cache miss with 8 bubbles
- **THEN** the scheduler issues exactly one LLM batch request containing pages 1, 2, 3, 4, 5

#### Scenario: Bubble-count threshold forces an earlier flush
- **WHEN** user batch-translates pages 1 through 5 with a context-consuming LLM engine
- **AND** pages 1, 2, 3 each have 20 bubbles and pages 4, 5 each have 5 bubbles, all misses
- **THEN** the scheduler issues a batch containing pages 1 and 2 (total 40 bubbles), then a batch containing pages 3, 4, and 5 (total 30 bubbles)

#### Scenario: Page-count cap forces a flush even when bubble count fits
- **WHEN** user batch-translates pages 1 through 8 with a context-consuming LLM engine
- **AND** each page has 4 bubbles, all misses
- **THEN** the scheduler issues a batch containing pages 1 through 5, then a batch containing pages 6, 7, 8

#### Scenario: Single page exceeding bubble threshold forms a batch of one
- **WHEN** user batch-translates pages 1 and 2 with a context-consuming LLM engine
- **AND** page 1 has 60 bubbles and page 2 has 10 bubbles, both misses
- **THEN** the scheduler issues a batch containing only page 1, then a batch containing only page 2 (because page 1's size flushed the group before page 2 could be appended)

#### Scenario: Per-page retranslate skips batch grouping
- **WHEN** user clicks retranslate on a single page with a context-consuming LLM engine
- **THEN** the system calls the per-page translation service method for that page
- **AND** the system does not construct a batch group

#### Scenario: DeepL batch translation does not use multi-page grouping
- **WHEN** user batch-translates pages 1 through 5 with DeepL
- **THEN** the scheduler does not issue any multi-page LLM batch request
- **AND** the existing DeepL per-page pipeline runs

### Requirement: Batch failure retry and per-page fallback
The system SHALL retry a failed multi-page LLM batch request exactly once before falling back to per-page translation.

A batch request is considered failed when any of the following occurs:

- The HTTP response status is not in the 200–299 range.
- A transport-level error occurs (timeout, connection failure, or any other non-cancellation `URLError`).
- The response body fails to parse as the expected multi-page response schema.
- The response parses as valid JSON but does not contain a translation for every requested page identifier.
- The response parses as valid JSON but contains one or more page identifiers that were not requested.
- The response parses as valid JSON but repeats the same page identifier, omits a requested bubble index for a page, or contains a bubble index for a page that was not requested.

User-initiated cancellation SHALL NOT be treated as a failed batch request. Cancellation errors from Swift concurrency (`CancellationError`), `URLSession` (`URLError.cancelled`), or service wrappers SHALL propagate to the scheduler without retry, error sanitization, or per-page fallback. The system SHALL treat every `URLError.cancelled` as a user-cancellation signal; it SHALL NOT attempt to distinguish OS-initiated request cancellation from user-initiated cancel, because in practice the only path that produces `URLError.cancelled` inside this pipeline is the cooperative cancellation triggered by the user's cancel action.

On the first failure, the system SHALL retry the same batch request after an exponential backoff delay starting at 500ms with a 2x multiplier on the first retry.

If the retry also fails for any of the same non-cancellation reasons, the system SHALL finalize each page in the failed batch group by calling the per-page translation service method in page-index order. The per-page fallback path SHALL use the same per-page service method, recent-context window, and per-page retry semantics that the per-page translation entry point uses.

The system SHALL log each batch failure and each fallback transition through `DebugLogger` with a stable category so the batch-failure rate can be observed.

#### Scenario: Transient HTTP failure recovers on retry
- **WHEN** the first attempt of a batch request returns HTTP 503
- **AND** the retry attempt returns HTTP 200 with a valid multi-page response
- **THEN** all pages in the batch finalize with the retry's results
- **AND** no per-page fallback is triggered

#### Scenario: Two consecutive failures fall back to per-page
- **WHEN** the first attempt of a batch request returns HTTP 500
- **AND** the retry attempt returns HTTP 500
- **THEN** the system calls the per-page translation service for each page in the batch in page-index order
- **AND** each page that succeeds per-page transitions to the `.translated` state
- **AND** each page that fails per-page transitions to the `.error` state per existing per-page failure rules

#### Scenario: Missing page identifier in response triggers retry then fallback
- **WHEN** a batch request for pages 1, 2, 3 returns HTTP 200 with translations for pages 1 and 2 only
- **AND** the retry attempt also returns HTTP 200 with translations for pages 1 and 2 only
- **THEN** the system finalizes pages 1, 2, and 3 by calling the per-page translation service for each in page-index order

#### Scenario: Unexpected page identifier in response triggers retry then fallback
- **WHEN** a batch request for pages 1, 2, 3 returns HTTP 200 with translations for pages 1, 2, 3, and 9
- **AND** the retry attempt also returns HTTP 200 with translations for pages 1, 2, 3, and 9
- **THEN** the system rejects the batch response
- **AND** the system finalizes pages 1, 2, and 3 by calling the per-page translation service for each in page-index order

#### Scenario: User cancellation skips retry and fallback
- **WHEN** a batch request is in flight
- **AND** the user cancels the batch translation run
- **THEN** the batch request is cancelled without retry
- **AND** no per-page fallback is triggered for that cancelled batch

#### Scenario: Per-page fallback observes the same rolling-window contents
- **WHEN** a batch request for pages 3, 4, 5 fails and falls back to per-page
- **AND** the rolling window before the batch contained pages 1 and 2 (with page 1 sourced from cache hit)
- **THEN** page 3's per-page request observes recent context for pages 1 and 2
- **AND** after page 3 succeeds, page 4's per-page request observes recent context for pages 1, 2, and 3
- **AND** after page 4 succeeds, page 5's per-page request observes recent context for pages 2, 3, and 4

### Requirement: Mid-batch cancellation is atomic
The system SHALL treat each multi-page LLM batch request as the atomic unit of cancellation during batch translation.

When the user cancels batch translation while a batch request's LLM call is in flight, the system SHALL:

- Cancel the in-flight URL request and discard any partially received response body.
- Return every page in the cancelled batch to the `.pending` state.
- Not start any later batch.
- Set `isProcessing` to `false` after the scheduler exits.

The system SHALL NOT append any page from a cancelled batch to the rolling recent-context window.

Pages that have already completed before the cancel point SHALL retain their final state:

- Cache-hit pages already transitioned to `.translated` SHALL remain `.translated` and SHALL remain in the rolling window.
- Prior batches' successfully translated pages SHALL remain `.translated` and SHALL remain in the rolling window.
- Prior batches that fell back to per-page and succeeded SHALL retain their per-page results.

#### Scenario: Cancel during in-flight batch returns batch pages to pending
- **WHEN** a batch request grouping pages 4, 5, 6 is in flight
- **AND** the user cancels the batch translation run
- **THEN** pages 4, 5, and 6 transition to `.pending`
- **AND** the underlying URL request is cancelled
- **AND** no `.error` state is recorded for those pages

#### Scenario: Cancel does not start the next batch
- **WHEN** the user cancels the batch translation run while a batch is in flight
- **AND** the next batch grouping pages 7, 8 has not yet been issued
- **THEN** pages 7 and 8 remain in their current pre-batch state (`.pending` or `.processing` per existing rules)
- **AND** no LLM call is made for pages 7 or 8

#### Scenario: Cancel preserves prior batches' results and rolling window
- **WHEN** pages 1, 2, 3 finalized via a previous successful batch and contribute to the rolling window
- **AND** the user cancels during the batch grouping pages 4, 5, 6
- **THEN** pages 1, 2, 3 remain `.translated`
- **AND** the rolling window after cancel still contains pages 1, 2, 3
- **AND** pages 4, 5, 6 are not in the rolling window
