## Context

`TranslationViewModel.translatePage(at:bypassCache:)` is the single entry point for processing a page. Its current structure is:

1. Compute image hash
2. Check cache
3. Run OCR (`ocrRouter.processPage`)
4. After OCR: check `sourceLanguage == targetLanguage` → passthrough OR filter punct-only, translate

Problems:
- Step 3 (OCR, which may load a model) runs even when source == target and the result would be discarded.
- Punctuation-only bubbles return from OCR and get passthrough-mapped to `TranslatedBubble`, appearing in the sidebar as meaningless entries.
- The `sourceLanguage == targetLanguage` check is duplicated (once to skip API key validation, once post-OCR).
- There is no log entry explaining why a page or bubble produced no translation output.

## Goals / Non-Goals

**Goals:**
- Skip OCR entirely when `sourceLanguage == targetLanguage`.
- After OCR, discard any bubble whose text is empty or consists entirely of punctuation/whitespace characters; do not pass these to the translation engine or the sidebar.
- Emit a log entry with `level`, `category: .pipeline`, and a `metadata` dictionary (`reason`, `page_index`, `source_language`, `target_language` for same-language bypass; `filtered_count`, `total_count`, `page_index` for meaningless-bubble filter) for every bypass decision.
- Add a `.pipeline` category to `DebugLogCategory` for these events.
- Remove the redundant `needsTranslation` variable and the duplicate post-OCR same-language branch.

**Non-Goals:**
- No changes to OCR engines, translation service protocols, or cache key structure.
- No new UI surfaces (sidebar already shows empty state when `translated == []`).
- No cache write for the same-language bypass (it is a settings condition, not image-specific).
- No changes to how the translation services themselves handle empty input.

## Decisions

**D1: Where to place the same-language guard**
Placing the guard as the first statement in the pipeline (before image hash and OCR) keeps the bypass cheap and obvious. Alternative: keep it post-OCR and just skip the API call. Rejected because it still loads the OCR model unnecessarily.

**D2: Definition of "meaningless" bubble**
A bubble is meaningless if `text.allSatisfy { $0.isPunctuation || $0.isWhitespace }`. This includes empty strings (vacuous truth in Swift). This matches the existing filter logic that was already applied inside the `else` branch, so the change is a promotion, not a new heuristic. Alternatives such as regex or minimum-character-count thresholds were not needed and add complexity.

**D3: Meaningless bubbles are dropped, not passthroughed**
The old code added punct-only bubbles back into `translated` as passthrough `TranslatedBubble` entries. The new code drops them before translation. They will not appear in the sidebar. This is the user's explicit requirement. Risk: if some future consumer expects all OCR-detected bubbles to appear in output regardless of content, this will break. Accepted because the sidebar is the only consumer.

**D4: Log category `.pipeline`**
Pipeline skip decisions are not OCR events (`.ocrRouter`, `.ocrManga`, `.ocrPaddle`) nor translation events. A new `.pipeline` category makes these decisions easily filterable in the debug log view without noise from engine-level logging.

**D5: No cache write for same-language bypass**
The bypass fires before image-hash computation, so there is no hash to key on. More importantly, the bypass is a settings-only decision: the image has not been analysed and the empty result carries no information about its content. Caching an empty array would pollute the cache with content-free entries. The cache key already includes `(source, target, engine)`, so a later language-pair change would produce a cache miss anyway — but skipping the write is still correct because no OCR was performed and there is nothing meaningful to cache.

## Risks / Trade-offs

- **[Risk] Vacuous truth on empty OCR result** — `[].allSatisfy(...)` is `true`, so an empty OCR array is already classified as "all meaningless". The pipeline correctly produces `.translated([])`. No special case needed. Verified correct.
- **[Risk] Removing passthrough bubbles breaks overlay rendering** — The image viewer overlays bubbles from the `translated` array. Dropping punctuation-only bubbles means their bounding boxes no longer get overlays. This is acceptable and desirable; punctuation markers are not useful overlays.
- **[Trade-off] Same-language pages show empty sidebar** — The sidebar shows the "No translations yet" empty state for same-language pages. This is intentional; OCR was not run so there is nothing to show.
