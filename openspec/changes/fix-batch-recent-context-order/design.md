## Context

`TranslationViewModel` currently stores recent-page context in `recentPageTranslations`, builds context immediately before each page translation, and appends translated text after each page finishes. `translateBatch()` and `retranslateAllPages()` both process up to three pages concurrently by calling `translatePage(at:)`.

That structure is unsafe for contextual LLM translation. If page 2 finishes before page 1, page 3 can observe a context window that is missing page 1 or ordered by completion time rather than page index. The spec requires context to represent prior pages, not prior completed tasks.

The implementation also has adjacent constraints that must be preserved:

- DeepL and Google use `TranslationContext.glossaryTerms` for glossary substitution even though they do not use recent-page summaries.
- Translation cache hits skip OCR and translation, but the cached translated text is still the final page text visible to the user.
- A failed page has no final translated text and must not become context for later pages.
- Re-translate-all is another batch pipeline entry point and must not retain the old concurrent recent-context behavior.
- Single-page translation may still use the in-memory recent context accumulated by prior single-page operations.

## Goals

- Make LLM batch recent context deterministic and page-index ordered.
- Preserve concurrency for OCR, image loading, image hashing, and cache lookup where those steps do not consume recent-page context.
- Preserve glossary behavior for all engines that currently use glossary terms.
- Preserve cache-hit behavior while letting cached final translated text participate in later LLM context.
- Keep failed pages isolated from later recent context while allowing later pages to proceed.
- Apply one coherent semantic model to both initial batch translation and batch re-translation.

## Non-Goals

- No UI redesign or progress UI replacement.
- No translation cache schema or cache-key changes.
- No persisted recent-context storage.
- No change to prompt wording beyond whether recent-page summaries are present and ordered.
- No change to DeepL or Google glossary substitution behavior.
- No new translation engine.

## Design

### Context Ownership

The batch pipeline should treat recent-page context as a page-index-derived sequence of final translated page summaries. A page summary is the page's translated bubbles sorted by `TranslatedBubble.index`, joined with spaces, matching the existing `appendToRecentContext` behavior.

Only pages with a final successful translated result contribute summaries. A page contributes whether its result came from a translation API call or a translation-cache hit. A same-language skip or all-meaningless OCR result produces a successful empty translation result; it may be represented as an empty summary only if doing so is necessary to preserve the existing rolling-window counting semantics. A failed page contributes nothing.

The rolling window size remains 3 summaries. For page N, recent context may include only successful pages with page index lower than N, keeping the most recent 3 such summaries in ascending page-index order.

### Engine Boundary

Use an explicit predicate, such as `usesRecentPageContext(engine:)`, whose true cases are `.openAI` and `.githubCopilot`.

For engines that use recent context:

- Translation calls receive glossary terms plus page-ordered recent-page summaries.
- Batch translation calls that need recent context run in ascending page-index order after their page preparation is available.
- Cache-hit pages do not call the translation service but still update the batch recent-context window from cached translated bubbles.

For engines that do not use recent context:

- Translation calls receive glossary terms when an active glossary exists.
- `recentPageSummaries` is always empty.
- Pages do not read from or append to `recentPageTranslations`.
- Page translation may remain concurrent, subject to the existing batch concurrency limit.

### Batch Pipeline

The implementation should avoid calling the current full `translatePage(at:)` concurrently for LLM batch work because that method both consumes and mutates recent context.

A safe shape is:

1. Prepare pages with bounded concurrency:
   - Validate page index and language pair.
   - Load image if needed.
   - Compute or reuse image hash.
   - Check translation cache when cache is not bypassed.
   - Run OCR and filter meaningless bubbles when cache misses.
   - Store enough intermediate data to translate or finalize the page later.
2. Finalize pages in page-index order for context-consuming LLM engines:
   - If preparation failed, mark the page error and do not update recent context.
   - If preparation produced a cache hit, set final page state and append cached translated text to the batch recent-context window.
   - If preparation produced no meaningful bubbles, set final page state, store cache as appropriate, and update recent context according to the chosen empty-summary rule.
   - If translation is needed, build context from active glossary terms plus the current page-ordered recent-context window, call the translation service, store cache, update page state, then append the translated summary.
3. For non-contextual engines, pages may translate after preparation without waiting for lower page indexes, but they must receive an empty `recentPageSummaries` array.

The same helper pipeline should back both `translateBatch()` and `retranslateAllPages()`. The only required behavioral difference is cache policy: initial batch may use cache, while re-translate-all bypasses cache lookup and overwrites cache with fresh OCR plus translation results.

### Single-Page Translation

`translatePage(at:bypassCache:)` must remain usable outside batch operations. It may continue to use the current in-memory `recentPageTranslations` behavior for single-page sequential usage, but it must respect the engine boundary:

- LLM engines may receive current recent-page summaries.
- DeepL and Google must receive glossary terms with empty recent-page summaries.
- DeepL and Google must not append to `recentPageTranslations`.
- LLM cache hits should update recent context when they represent a successful final translated page, so subsequent single-page translations observe the same semantic source as batch translations.

### Failure Handling

Failure is page-local. OCR, image loading, cache decoding, or translation failure for page N must not add anything to recent context. Later pages may proceed if their own preparation and translation succeed. For LLM batch translation, later pages still wait for lower indexes to be finalized or skipped so that the context window is known and deterministic.

When bypassing cache for a page that already had translated state, preserve the existing behavior of restoring previous translated state on failure where that behavior is already required by tests. A restored previous state should not be treated as a newly successful page for batch recent context unless the implementation explicitly finalizes it as the visible result for that batch page.

### Progress and UI State

Pages may enter `.processing` as soon as preparation starts. Pages should update to `.translated` or `.error` when their own final result is known. The deterministic LLM ordering requirement applies to context-consuming translation calls, not necessarily to when OCR begins.

## Risks

- Over-serializing all work would fix context order but regress batch throughput. Tests should assert OCR can start concurrently while LLM calls remain page-ordered.
- Passing `.empty` context to DeepL or Google would remove glossary substitution. Tests should assert glossary terms still flow to non-contextual engines.
- Treating cache hits as invisible to recent context would make cached and uncached batch runs produce different LLM prompts. Tests should assert cache-hit pages contribute cached translated text to later LLM context without invoking translation.
- Fixing only `translateBatch()` would leave `retranslateAllPages()` nondeterministic. Tests should cover both entry points.

## Open Questions

(none)
