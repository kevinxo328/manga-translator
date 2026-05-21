## Why

`CacheService` currently swallows every SQLite failure: `sqlite3_open` errors only emit a log line, mutation results (`sqlite3_exec`, `sqlite3_step`) are ignored, and callers receive `Void` returns that imply success even when the database is unusable. As a result, `clearAll()` can fail while `TranslationViewModel` still resets every page to `.pending`, and `GlossaryService.deleteGlossary` can split a glossary from its terms because its two-step delete is neither transactional nor checked. The cache spec already requires that lookups return `nil` after `clearAll()`, but it does not yet describe what callers must observe when an operation fails. We need that contract before we can stop silent corruption.

## What Changes

- **BREAKING**: `CacheService` mutation API (`store`, `addHistory`, `clearAll`) becomes `throws`. Read API (`lookup`, `translationCacheSize`, `glossaryService` accessor) remains non-throwing.
- **BREAKING**: `GlossaryService` mutation API (`createGlossary`, `deleteGlossary`, `addTerm`, `updateTerm`, `deleteTerm`, plus auto-detected term inserts) becomes `throws`. Read API (`listGlossaries`, `listTerms`) remains non-throwing.
- Add `CacheService.isAvailable: Bool` (true when the database is open and `PRAGMA foreign_keys = ON` succeeded; false otherwise). The flag is set once during `init` and does not change at runtime.
- `CacheService.init` keeps its non-throwing signature. When the database cannot be opened or `PRAGMA foreign_keys = ON` fails, `init` records the failure, sets `isAvailable = false`, and returns. All subsequent mutation calls throw `CacheError.unavailable`; all subsequent read calls return the documented degraded values (`nil`, `[]`, `0`) without throwing.
- Wrap `GlossaryService.deleteGlossary` in an explicit SQLite transaction (`BEGIN IMMEDIATE` → delete terms → delete glossary → `COMMIT`; `ROLLBACK` on any failure). Schema is **not** changed; no migration is written.
- Enable `PRAGMA foreign_keys = ON` once, immediately after `sqlite3_open` succeeds.
- `TranslationViewModel.clearCacheAndResetPages()` only resets page state when `clearAll()` returns successfully. On failure, page state is preserved and `errorMessage` is populated with a generic string: `"Failed to clear cache. Translations may still be cached. Please restart the app if the problem persists."`. The underlying SQLite error message is forwarded to `DebugLogger`, not the UI.
- Other mutation callers (`addHistory`, `store` from translation pipeline) silently swallow `CacheError.unavailable` and log to `DebugLogger`; they do not interrupt the translation flow. This preserves the existing behaviour where a missing cache must not prevent translation.
- No startup-time alert. `isAvailable == false` only becomes visible through the next user-triggered mutation failure (`clearCacheAndResetPages` or glossary edits).

## Capabilities

### New Capabilities
- _(none)_

### Modified Capabilities
- `cache-management`: adds failure-observability requirements (mutation throws, `isAvailable` flag, PRAGMA foreign_keys enforced on open) and refines `clearAll()` / page-reset semantics so the UI does not reset pages when the cache mutation fails.
- `glossary-management`: requires `deleteGlossary` to be atomic via an explicit transaction, so a failure cannot leave terms without their parent glossary (or vice versa).

## Impact

- Code:
  - `MangaTranslator/Services/CacheService.swift` (introduce `isAvailable`, throws-based mutations, PRAGMA enable, error type)
  - `MangaTranslator/Services/GlossaryService.swift` (transactional `deleteGlossary`, throws-based mutations)
  - `MangaTranslator/ViewModels/TranslationViewModel.swift` (call sites add `try?`/`try`, `clearCacheAndResetPages` preserves state on failure and sets `errorMessage`)
  - `MangaTranslator/Views/GlossaryView.swift` and any other glossary call sites (handle `throws` from glossary mutations)
- Tests:
  - `MangaTranslatorTests/CacheServiceTests.swift` (open failure, mutation throws, PRAGMA enabled, glossary delete atomicity)
  - `MangaTranslatorTests/TranslationViewModelTests.swift` (page state preservation, alert message, debug log routing)
- Not in scope:
  - Schema changes, ON DELETE CASCADE, migrations of existing user databases.
  - Cache key, table names, column layout, or serialized cache payload format.
  - Archive import, OCR pipeline, model lifecycle, translation provider error sanitization (Task 6), or `KeychainService` (Task 5).
