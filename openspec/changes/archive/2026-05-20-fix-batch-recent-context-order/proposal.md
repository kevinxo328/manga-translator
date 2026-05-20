## Why

Batch translation currently allows multiple pages to build and append recent-page context concurrently. Because completion order can differ from page order, an LLM translation may receive missing, future, or misordered prior-page context, which makes batch output nondeterministic and violates the contextual translation contract.

The fix needs a formal change because the expected behavior crosses batch processing, cache hits, failed pages, re-translate-all, non-LLM engines, and glossary injection. Capturing those boundaries in the spec avoids a narrow race-condition fix that accidentally removes glossary context or changes cache semantics.

## What Changes

- Define that recent-page context for LLM engines is ordered only by page index, never by async completion order.
- Define a batch boundary where OCR, image analysis, and cache lookup may remain concurrent, while LLM translation that consumes recent-page context must run in page-index order.
- Define that cached translated pages contribute their cached translated text to later LLM recent context without re-running OCR or translation.
- Define that failed pages do not contribute to later recent context, and later pages continue when their own prerequisites succeed.
- Define that DeepL and Google do not receive recent-page summaries and do not write to the recent-page context window.
- Preserve glossary context for engines that use glossary substitution, including DeepL and Google.
- Apply the same page-ordered recent-context semantics to both initial batch translation and batch re-translation.
- No user-facing UI changes and no intentional cache-key or persisted-data migration.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `contextual-translation`: Clarifies deterministic page-ordered recent context during batch work, cache-hit participation, failure behavior, non-LLM engine behavior, glossary coexistence, and batch re-translation semantics.

## Impact

- Affected code:
  - `MangaTranslator/ViewModels/TranslationViewModel.swift`
  - `MangaTranslatorTests/TranslationViewModelTests.swift`
  - Test doubles in `TranslationViewModelTests.swift`
- Internal behavior:
  - Batch processing needs a coordinator that separates concurrent page preparation from page-ordered context-consuming LLM translation.
  - `translateBatch()` and `retranslateAllPages()` need to share the same contextual batch semantics.
  - Single-page translation remains supported and must not require the batch coordinator.
- APIs and dependencies:
  - No new external dependencies expected.
  - Avoid public protocol or initializer changes unless tests cannot express the behavior otherwise; if changed, update immediate callers and fakes.
