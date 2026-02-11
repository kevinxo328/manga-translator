## Why

The current re-translate feature only re-runs translation on existing OCR results, skipping OCR entirely. When the OCR engine or detection model improves, or when the original OCR produced incorrect text, users have no way to refresh the OCR results without clearing the entire cache and re-processing all pages. Re-translate should perform a full OCR + translate pipeline and write the fresh results back to cache.

## What Changes

- **BREAKING**: Re-translate now performs full OCR re-processing before translation, replacing the previous behavior of reusing existing OCR results
- The re-translate action calls the OCR pipeline first, then translates the new OCR results, then overwrites the cache entry with the complete new results
- Remove the `retranslateFromOCR()` method that only re-translates from existing bubbles
- The re-translate button behavior changes: it now triggers a full page reprocessing (OCR + translate), not just re-translation

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `retranslate`: Re-translate now includes re-running OCR before translation, instead of reusing existing OCR results. The cache entry is overwritten with the new OCR + translation results.

## Impact

- `TranslationViewModel.swift`: Replace `retranslateFromOCR()` with a method that calls the full OCR → translate → cache store pipeline (bypassing cache lookup)
- `TranslationSidebar.swift`: Button action changes to call the new full re-translate method
- `CacheService.swift`: No changes needed — existing `store()` already overwrites entries
- Existing `retranslate` spec needs a delta spec to reflect the new OCR-inclusive behavior
