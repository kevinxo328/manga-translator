## Context

Translation results are cached in a SQLite database (`translation_cache` table) keyed by image hash, source/target language, and engine. OCR results are not persisted on disk — they live only in memory as `PageState`. When a user changes OCR or translation settings, stale cached results are served instead of fresh ones. There is no UI to clear the cache.

The `CacheService` is instantiated as a private property of `TranslationViewModel`. The `SettingsView` currently has no reference to `CacheService` or `TranslationViewModel`.

## Goals / Non-Goals

**Goals:**
- Allow users to clear all cached translation results from the Settings view
- Reset in-memory page states so re-translation runs fresh OCR + translation
- Simple one-button interaction — no selective/partial clearing

**Non-Goals:**
- Selective cache clearing (per-image, per-language, per-engine)
- Clearing history records
- Cache size display or statistics

## Decisions

### 1. Pass a closure from TranslationViewModel to SettingsView

**Decision**: SettingsView receives an optional `onClearCache` closure. When provided, the button is shown. The closure calls `CacheService.clearAll()` and resets all page states.

**Why not inject CacheService directly**: SettingsView shouldn't know about CacheService or TranslationViewModel internals. A closure keeps coupling minimal and the view reusable.

**Why optional**: SettingsView may be opened from contexts where no ViewModel exists (e.g., app launch before loading files). The button simply hides when no closure is provided.

### 2. DELETE FROM instead of DROP TABLE

**Decision**: Use `DELETE FROM translation_cache` rather than dropping and recreating the table.

**Why**: Simpler, preserves table schema, no risk of schema mismatch. Performance difference is negligible for this use case.

### 3. Reset pages to .pending after clearing

**Decision**: After clearing the DB cache, reset all loaded pages' state to `.pending` so the next translation cycle re-runs OCR and translation from scratch.

**Why**: This is the user's expected behavior — "clear cache" means "forget everything and redo."

## Risks / Trade-offs

- [No undo] → Acceptable for cache clearing; cache is rebuilt on next translation
- [No confirmation dialog yet] → Add a confirmation alert to prevent accidental clearing
