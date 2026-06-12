## MODIFIED Requirements

### Requirement: Multi-page LLM batch grouping
The system SHALL group consecutive miss pages into multi-page LLM batch requests when batch translation runs with a context-consuming LLM engine (GitHub Copilot or OpenAI Compatible).

Batch translation SHALL be pipelined: page preparation (OCR, cache lookup) and LLM consumption run concurrently. A single ordered consumer SHALL consume preparations strictly in ascending page-index order; a page's preparation result is consumable only when the results of all lower-index pages have already been consumed. The consumer SHALL NOT wait for all pages to finish preparation before dispatching the first LLM batch request.

Batch groups SHALL be formed with a ramp-up page cap: the k-th dispatched LLM batch group in a run has page cap `ramp[k]`, where `ramp = [1, 3, 5, 5, 5, ...]`. Only dispatched LLM batch groups advance the ramp ordinal; pages that finalize individually (cache hits, skips, failures) do not consume a ramp slot. Group composition SHALL be a pure function of page order, bubble counts, and per-page preparation outcomes; OCR or LLM timing SHALL NOT affect which pages form a group.

A batch group is formed by appending consecutive pages whose preparation produced fresh OCR results (not a translation-cache hit), starting at the next unconsumed index, while all of the following invariants hold:

- The sum of bubble counts across all pages in the group, including the next candidate, is at most 45.
- The number of pages in the group, including the next candidate, is at most the current ramp cap (which never exceeds 5).

The system SHALL dispatch the group when any of the following occurs:

- The group has reached the current ramp cap.
- Appending the next prepared page would exceed the bubble invariant.
- The next prepared page is a translation-cache hit. Cache-hit pages SHALL NOT enter any batch group.
- The next prepared page is a skip or failure (these finalize individually and act as group boundaries).
- The page list is exhausted.

While a group has not yet reached a dispatch condition, the consumer waits for the next page's preparation; an in-flight LLM request is never delayed by waiting preparations, and preparations continue while an LLM request is in flight.

A single page whose bubble count exceeds 45 SHALL form a batch group of exactly one page; the system SHALL NOT split such a page across multiple groups.

The pipelined dispatch SHALL NOT change rolling-window semantics: because consumption is strictly page-index ordered, every rolling-window observation at a batch boundary and every append after a successful batch SHALL occur in ascending page-index order, exactly as a sequential page-index walk of the same groups would produce.

Per-page translation entry points (single-page retranslate via `translatePage(at:bypassCache:)`) SHALL NOT use the multi-page batch grouping path. They SHALL continue to call the per-page translation service method directly.

DeepL and Google Translate SHALL NOT use the multi-page batch grouping path. Their existing per-page parallel pipeline is unchanged.

#### Scenario: First batch dispatches after page 1's preparation alone
- **WHEN** user batch-translates pages 1 through 6 with a context-consuming LLM engine
- **AND** page 1's preparation completes while pages 2 through 6 are still preparing
- **THEN** the scheduler dispatches an LLM batch request containing only page 1
- **AND** preparation of later pages continues while that request is in flight

#### Scenario: Ramp-up grouping of a uniform miss run
- **WHEN** user batch-translates pages 1 through 8 with a context-consuming LLM engine
- **AND** each page is a cache miss with 4 bubbles
- **THEN** the scheduler issues exactly three LLM batch requests: pages [1], pages [2, 3, 4], and pages [5, 6, 7, 8]

#### Scenario: Ramp reaches and holds the full page cap
- **WHEN** user batch-translates pages 1 through 12 with a context-consuming LLM engine
- **AND** each page is a cache miss with 4 bubbles
- **THEN** the scheduler issues batch requests for pages [1], [2, 3, 4], [5, 6, 7, 8, 9], and [10, 11, 12]

#### Scenario: Out-of-order preparation completion does not reorder consumption
- **WHEN** page 3's preparation completes before page 2's during a batch run (for example, page 3 is a cache hit while page 2 is still in OCR)
- **THEN** page 3 is not finalized until page 2's preparation result has been consumed
- **AND** rolling-window observations remain in ascending page-index order

#### Scenario: Bubble-count threshold forces an earlier flush within a ramp cap
- **WHEN** user batch-translates pages 1 through 5 with a context-consuming LLM engine
- **AND** pages 1, 2, 3 each have 20 bubbles and pages 4, 5 each have 5 bubbles, all misses
- **THEN** the scheduler issues batch requests for pages [1] (ramp cap 1), pages [2, 3, 4] (20 + 20 + 5 = 45 bubbles, at the bubble cap), and pages [5]

#### Scenario: Single page exceeding bubble threshold forms a batch of one
- **WHEN** user batch-translates pages 1 and 2 with a context-consuming LLM engine
- **AND** page 1 has 60 bubbles and page 2 has 10 bubbles, both misses
- **THEN** the scheduler issues a batch containing only page 1, then a batch containing only page 2

#### Scenario: Cache hit acts as a boundary and does not consume a ramp slot
- **WHEN** user batch-translates pages 1 through 5 with a context-consuming LLM engine
- **AND** page 3 has a valid translation-cache hit and pages 1, 2, 4, 5 are misses with 8 bubbles each
- **THEN** the scheduler issues batch requests for pages [1] (ramp cap 1), pages [2] (ramp cap 3, cut short by the cache-hit boundary), and pages [4, 5] (ramp cap 5)
- **AND** page 3 is never sent in an LLM batch request
- **AND** the [4, 5] batch's recent context includes page 3's cached translated bubbles in ascending page-index order

#### Scenario: Per-page retranslate skips batch grouping
- **WHEN** user clicks retranslate on a single page with a context-consuming LLM engine
- **THEN** the system calls the per-page translation service method for that page
- **AND** the system does not construct a batch group

#### Scenario: DeepL batch translation does not use multi-page grouping
- **WHEN** user batch-translates pages 1 through 5 with DeepL
- **THEN** the scheduler does not issue any multi-page LLM batch request
- **AND** the existing DeepL per-page pipeline runs

### Requirement: Mid-batch cancellation is atomic
The system SHALL treat each multi-page LLM batch request as the atomic unit of cancellation during batch translation.

When the user cancels batch translation while a batch request's LLM call is in flight, the system SHALL:

- Cancel the in-flight URL request and discard any partially received response body.
- Return every page in the cancelled batch to the `.pending` state.
- Not start any later batch.
- Stop page preparations that have not yet completed and discard preparation results that have not yet been consumed.
- Return every page that has not finalized — including pages whose preparation was in flight or whose completed preparation was never consumed — to the `.pending` state.
- Apply all revert transitions only after both the preparation producer and the consumer have stopped, so no late preparation result can overwrite a reverted page state.
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

#### Scenario: Cancel reverts pages still in preparation
- **WHEN** a batch request grouping pages 1, 2 is in flight
- **AND** pages 3 and 4 are still preparing and page 5's completed preparation has not been consumed
- **AND** the user cancels the batch translation run
- **THEN** pages 1 through 5 all transition to `.pending` after the scheduler exits
- **AND** no LLM call is made for pages 3, 4, or 5

#### Scenario: Cancel does not start the next batch
- **WHEN** the user cancels the batch translation run while a batch is in flight
- **AND** the next batch grouping pages 7, 8 has not yet been issued
- **THEN** pages 7 and 8 transition to `.pending` after the scheduler exits
- **AND** no LLM call is made for pages 7 or 8

#### Scenario: Cancel preserves prior batches' results and rolling window
- **WHEN** pages 1, 2, 3 finalized via a previous successful batch and contribute to the rolling window
- **AND** the user cancels during the batch grouping pages 4, 5, 6
- **THEN** pages 1, 2, 3 remain `.translated`
- **AND** the rolling window after cancel still contains pages 1, 2, 3
- **AND** pages 4, 5, 6 are not in the rolling window
