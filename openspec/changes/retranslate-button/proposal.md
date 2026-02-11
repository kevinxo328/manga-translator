## Why

When viewing a translated image, users may want to re-translate using a different translation engine or updated settings without re-running OCR. Currently, the only option is to clear all cache and retranslate everything. A targeted "re-translate" button in the translation sidebar would let users force re-translation of the current page using existing OCR results, saving time and API costs.

## What Changes

- Add a "Re-translate" button to the `TranslationSidebar` header area, visible when translations exist
- Add a `retranslateCurrentPageFromOCR()` method to `TranslationViewModel` that:
  - Extracts OCR bubbles from the current translated state (skipping OCR)
  - Runs translation with current engine/language settings
  - Overwrites the cache entry with new results
- The button should show a loading state while re-translating

## Capabilities

### New Capabilities
- `retranslate`: Force re-translation of the current page using existing OCR results, bypassing cache lookup and OCR, then writing updated results back to cache

### Modified Capabilities
- `translation-cache`: Add support for upserting (overwriting) existing cache entries when re-translating

## Impact

- **UI**: `TranslationSidebar.swift` — add re-translate button
- **ViewModel**: `TranslationViewModel.swift` — add method to re-translate from existing OCR data
- **Cache**: `CacheService.swift` — ensure store overwrites existing entries (INSERT OR REPLACE behavior)
- **Models**: May need to extract `BubbleCluster` from `TranslatedBubble` for re-translation input
