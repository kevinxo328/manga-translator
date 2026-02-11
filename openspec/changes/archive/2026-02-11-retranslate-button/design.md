## Context

When a page is translated, the result is cached by (image_hash, source_lang, target_lang, engine). If the user changes translation engine or wants a fresh translation, `translatePage()` will hit the cache and return the old result. The only workaround today is clearing all cache via Settings, which is destructive and slow for batch workflows.

The `TranslatedBubble` model already contains the original `BubbleCluster` (with bounding boxes and OCR text), so we can extract OCR results from the current translated state without re-running OCR.

`CacheService.store()` uses `INSERT OR REPLACE`, so overwriting an existing cache entry already works — no schema changes needed.

## Goals / Non-Goals

**Goals:**
- Allow users to re-translate the current page from the translation sidebar
- Reuse existing OCR results (skip OCR step) to save time and avoid redundant processing
- Write updated translation back to cache, overwriting the previous entry
- Show loading state during re-translation

**Non-Goals:**
- Re-running OCR (users who want fresh OCR should clear cache)
- Batch re-translate of all pages at once
- Undo/revert to previous translation

## Decisions

### Extract OCR bubbles from current translated state
The `TranslatedBubble.bubble` property holds the original `BubbleCluster`. We extract these to feed directly into `TranslationService.translate()`, bypassing both cache lookup and OCR.

**Alternative considered**: Store OCR results separately from translation results. Rejected because the data is already available in `TranslatedBubble` and adding separate OCR storage would add complexity without benefit.

### Add `retranslateFromOCR()` method to TranslationViewModel
A new method that:
1. Extracts `BubbleCluster` array from current `TranslatedBubble` state
2. Calls `translationService.translate()` with current language/engine settings
3. Calls `cacheService.store()` to overwrite the cache entry
4. Updates `pages[index].state` with new results

**Alternative considered**: Adding a `skipCache` parameter to `translatePage()`. Rejected because re-translate-from-OCR is a distinct operation — it must also skip OCR, not just cache. A separate method is clearer.

### Button placement in TranslationSidebar header
Add the re-translate button in the sidebar header row next to "Translations" title. This keeps it discoverable but unobtrusive. The button is only enabled when translations exist (page is in `.translated` state).

## Risks / Trade-offs

- [OCR results may be stale] → Acceptable trade-off; users who want fresh OCR can clear cache. The re-translate feature is specifically for changing translation settings while preserving OCR.
- [Button could be accidentally clicked] → Mitigated by showing a loading indicator; the operation is idempotent and non-destructive (old translation is simply replaced).
