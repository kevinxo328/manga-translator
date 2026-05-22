## 1. Red tests — `CacheServiceTests`

- [x] 1.1 Add `openFailureMakesServiceUnavailable`: construct `CacheService` with an unwritable database path (or injectable opener) and assert `isAvailable == false`, `try cache.clearAll()` throws `CacheError.unavailable`, and `cache.lookup(...)` returns `nil` without throwing
- [x] 1.2 Add `pragmaFailureMakesServiceUnavailable`: simulate `PRAGMA foreign_keys = ON` failure (e.g. via injectable opener that returns a handle which rejects the PRAGMA) and assert `isAvailable == false`, `try cache.clearAll()` throws `CacheError.unavailable`, and the underlying handle is closed (no leak)
- [x] 1.3 Add `clearAllFailureDoesNotReportSuccess`: configure the test database so `DELETE FROM translation_cache` fails (e.g. write-locked or read-only handle), call `try cache.clearAll()`, assert it throws a `CacheError` whose payload includes the SQLite result code and `sqlite3_errmsg` text
- [x] 1.4 Add `clearAllSuccessRemovesAllCachedRows`: store two entries, `try cache.clearAll()`, then `lookup` for both keys returns `nil` (regression guard for the existing happy path under the new throws signature)
- [x] 1.5 Add `storeFailureThrowsCacheError`: configure SQLite to reject the `INSERT`, call `try cache.store(...)`, assert it throws a `CacheError` carrying result code + message
- [x] 1.6 Add `addHistoryFailureThrowsCacheError`: same shape as 1.5 but exercising `addHistory`
- [x] 1.7 Add `foreignKeysAreEnabledAfterOpen`: open a real on-disk database, run `PRAGMA foreign_keys;`, assert the result is `1`
- [x] 1.8 Add `lookupOnUnavailableCacheReturnsNil`: with `isAvailable == false`, call `lookup`, assert it returns `nil` and does not throw
- [x] 1.9 Add `translationCacheSizeOnUnavailableCacheReturnsZero`: with `isAvailable == false`, call `translationCacheSize()`, assert it returns `0` and does not throw
- [x] 1.10 Add `listGlossariesOnUnavailableCacheReturnsEmpty`: with `isAvailable == false`, call `glossaryService.listGlossaries()`, assert it returns `[]` and does not throw

## 2. Red tests — `GlossaryService` atomicity

- [x] 2.1 Add `deleteGlossarySucceedsRemovesGlossaryAndTerms`: create a glossary, add two terms, `try glossaryService.deleteGlossary(id:)`, assert both `glossaries` and `glossary_terms` rows for that id are gone (regression guard for the existing happy path under the new throws + transaction signature)
- [x] 2.2 Add `deleteGlossaryRollsBackWhenTermsDeleteFails`: arrange the database so `DELETE FROM glossary_terms WHERE glossary_id = ?` fails (e.g. via an injectable sqlite executor or a forced FK violation), call `try glossaryService.deleteGlossary(id:)`, assert it throws and that both the `glossaries` row and every `glossary_terms` row are still present
- [x] 2.3 Add `deleteGlossaryRollsBackWhenGlossaryDeleteFails`: arrange the database so `DELETE FROM glossaries WHERE id = ?` fails after the terms delete succeeded inside the transaction, call `try glossaryService.deleteGlossary(id:)`, assert it throws and that the terms rolled back are restored and the glossary row is still present
- [x] 2.4 Add `deleteGlossaryOnUnavailableCacheThrowsUnavailable`: with `isAvailable == false`, call `try glossaryService.deleteGlossary(id:)`, assert it throws `CacheError.unavailable` and that no SQLite statement was prepared
- [x] 2.5 Add `glossaryAddTermFailureThrows`: configure SQLite to reject the term `INSERT`, call `try glossaryService.addTerm(...)`, assert it throws a `CacheError` carrying result code + message
- [x] 2.6 Add `glossaryAddTermViolatingForeignKeyThrows`: with `PRAGMA foreign_keys = ON` active and no parent glossary present, call `try glossaryService.addTerm(...)` with a non-existent `glossaryID`, assert it throws

## 3. Red tests — `TranslationViewModelTests`

- [x] 3.1 Add `viewModelDoesNotResetPagesWhenCacheClearFails`: install a `CacheService` test double whose `clearAll` throws, populate `viewModel.pages` with at least one `.translated` page and one with a non-nil `textPixelMask`, call `clearCacheAndResetPages()`, assert no page's `state` changed and no page's `textPixelMask` was cleared
- [x] 3.2 Add `viewModelSetsGenericErrorMessageWhenCacheClearFails`: same setup as 3.1, assert `viewModel.errorMessage == "Failed to clear cache. Translations may still be cached. Please restart the app if the problem persists."`
- [x] 3.3 Add `viewModelDoesNotLeakSqliteMessageToErrorMessage`: arrange the test double to throw a `CacheError` whose SQLite message is `"database is locked"`, call `clearCacheAndResetPages()`, assert `viewModel.errorMessage` does NOT contain `"database is locked"`
- [x] 3.4 Add `viewModelRoutesSqliteMessageToDebugLogger`: with the same arrangement as 3.3 and a `DebugLogger` test double, assert `DebugLogger` received an entry containing the operation identifier (e.g. `"CacheService.clearAll"`) and the SQLite text `"database is locked"`
- [x] 3.5 Add `viewModelResetsPagesWhenCacheClearSucceeds`: with a `clearAll` that returns normally, assert every page resets to `.pending` and every `textPixelMask` becomes `nil` (regression guard for the existing happy path under the new throws signature)
- [x] 3.6 Add `translationPipelineContinuesWhenStoreThrows`: configure `CacheService.store` to throw, run a translation through the view model, assert the resulting page state is `.translated` (not `.error`) and that `DebugLogger` received the failure
- [x] 3.7 Add `loadFilesContinuesWhenAddHistoryThrows`: configure `addHistory` to throw, exercise the archive-load path, assert the pages are still shown and that no error alert is presented

## 4. Verify red

- [x] 4.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/CacheServiceTests` and confirm every new test fails for the expected reason (missing API or unchanged behaviour)
- [x] 4.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests` and confirm every new view-model test fails for the expected reason

## 5. Implementation — `CacheService`

- [x] 5.1 Introduce a `CacheError` enum in `MangaTranslator/Services/CacheService.swift` with cases for `unavailable` and `sqlite(code: Int32, message: String, operation: String)` (or equivalent payload that satisfies the spec)
- [x] 5.2 Add a `let isAvailable: Bool` stored property on `CacheService`, initialised in `init`
- [x] 5.3 In `init`, replace the silent-log open path with: attempt `sqlite3_open_v2`; if it fails, set `isAvailable = false`, leave `db` nil, return; if it succeeds, run `sqlite3_exec(db, "PRAGMA foreign_keys = ON", ...)`; on PRAGMA failure, close the handle, set `isAvailable = false`, return; otherwise set `isAvailable = true` and proceed with table creation
- [x] 5.4 Wrap `sqlite3_exec`, `sqlite3_prepare_v2`, and `sqlite3_step` calls inside mutations in a helper that converts non-success results into a thrown `CacheError.sqlite(...)` carrying `sqlite3_errmsg(db)` and the failing operation name
- [x] 5.5 Convert `clearAll`, `store`, `addHistory` to `throws`; each MUST check `isAvailable` first and throw `CacheError.unavailable` when false
- [x] 5.6 Keep `lookup`, `translationCacheSize`, and the `glossaryService` accessor non-throwing; on `isAvailable == false` they MUST return `nil`, `0`, and a still-usable `GlossaryService` instance that itself returns degraded reads / throws on mutations

## 6. Implementation — `GlossaryService`

- [x] 6.1 Convert `createGlossary`, `deleteGlossary`, `addTerm`, `updateTerm`, `deleteTerm`, and auto-detected term inserts to `throws`, sharing the same `CacheError` type as `CacheService`
- [x] 6.2 In `deleteGlossary`, wrap the two `DELETE` statements in `BEGIN IMMEDIATE` / `COMMIT`, with `ROLLBACK` on any non-success result; throw the resulting `CacheError.sqlite(...)` to the caller
- [x] 6.3 Each mutation MUST check `cacheService.isAvailable` (or an equivalent signal injected at construction) and throw `CacheError.unavailable` without preparing any statement when the cache is unavailable
- [x] 6.4 Keep `listGlossaries` and `listTerms` non-throwing; on `isAvailable == false` they return `[]`
- [x] 6.5 Do NOT change schema, FK clauses, table names, or columns; do NOT write any migration code

## 7. Implementation — `TranslationViewModel`

- [x] 7.1 In `clearCacheAndResetPages()`, call `try cacheService.clearAll()` inside a `do` block; on success, run the existing page-reset loop; on `catch`, do NOT modify any page state, set `errorMessage` to the fixed string defined in `cache-management` spec, and forward the underlying SQLite text to `DebugLogger`
- [x] 7.2 At the four production mutation call sites (`addHistory` at line ~229, `store` at lines ~457 and ~481, `clearAll` at line ~512 — verify by re-grepping), add `try`/`try?` per spec: history/store failures are logged to `DebugLogger` but do NOT block the translation flow or alter the page state machine; only `clearCacheAndResetPages` shows an alert
- [x] 7.3 In `GlossaryView` (and any other glossary call site found via `rg -n "glossaryService\." -t swift`), wrap the mutation calls in `do`/`catch`; on failure, set `errorMessage` to `"Failed to update glossary. Please try again, or restart the app if the problem persists."` and forward the SQLite text to `DebugLogger`
- [x] 7.4 Do NOT add any startup-time `isAvailable` check or alert in `TranslationViewModel.init`; the spec forbids proactive notification
- [x] 7.5 Do NOT introduce a new `@Published` property for cache unavailability; reuse the existing `errorMessage` channel

## 8. Verify green

- [x] 8.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/CacheServiceTests` and confirm every test (existing + new) passes
- [x] 8.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests` and confirm every test (existing + new) passes
- [x] 8.3 Run `openspec validate harden-cache-service-error-reporting --strict` and confirm it returns no errors
- [x] 8.4 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests` once to confirm no unrelated tests regressed (smoke); if anything outside cache/glossary regressed, fix it before declaring done

## 9. Wrap-up

- [x] 9.1 Update PLAN.md Task 7's "驗證指令" block with the actual commands run, and mark each completion-definition checkbox once verified
- [x] 9.2 Note any skipped scenarios (e.g. tests that depend on environment-specific SQLite behaviour) and document the reason in the PR description, per PLAN.md `交付檢查清單`
