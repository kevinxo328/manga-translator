## Why

After translating manga pages, results are cached in a local SQLite database and reused on subsequent loads. When OCR parameters or translation settings change, stale cached results prevent users from seeing improved output. There is currently no way to clear this cache without manually deleting the database file.

## What Changes

- Add a `clearCache()` method to `CacheService` that deletes all rows from the `translation_cache` table
- Add a "Clear Cache" button in the Settings view (Preferences tab) that clears the on-disk translation cache and resets all in-memory page states to `.pending`
- After clearing, the current session's pages are reset so re-translating will run fresh OCR and translation

## Capabilities

### New Capabilities
- `cache-management`: Ability to clear all cached translation results from the settings page, forcing fresh OCR and translation on next run

### Modified Capabilities
<!-- None -->

## Impact

- **CacheService.swift**: New method to delete all rows from `translation_cache`
- **SettingsView.swift**: New button in Preferences tab
- **TranslationViewModel.swift**: Method to reset all page states to `.pending`
- No breaking changes, no API or dependency changes
