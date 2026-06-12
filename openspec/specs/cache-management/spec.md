## Purpose

Allows users to clear all cached translation results, forcing fresh OCR and translation on subsequent runs.

## Requirements

### Requirement: Clear all cached translations
The system SHALL provide a way to delete all rows from the `translation_cache` SQLite table via a single operation.

#### Scenario: Clear cache successfully
- **WHEN** `CacheService.clearAll()` is called
- **THEN** all rows in the `translation_cache` table SHALL be deleted
- **THEN** subsequent `lookup()` calls SHALL return `nil` for previously cached entries

### Requirement: Clear cache button in Settings
The system SHALL display a "Clear Cache" button in the Settings view Preferences tab. When the user confirms the action, the system SHALL attempt to clear the cache and SHALL reset page states only when the clear operation succeeds. When the clear operation fails, the system SHALL preserve page states and SHALL present a generic error alert.

#### Scenario: User taps Clear Cache
- **WHEN** user clicks the "Clear Cache" button
- **THEN** a confirmation alert SHALL be presented

#### Scenario: User confirms clearing and clear succeeds
- **WHEN** user confirms the clear cache alert
- **AND** `CacheService.clearAll()` returns successfully
- **THEN** all translation cache entries SHALL be deleted from disk
- **THEN** all loaded pages SHALL be reset to `.pending` state

#### Scenario: User confirms clearing but clear fails
- **WHEN** user confirms the clear cache alert
- **AND** `CacheService.clearAll()` throws
- **THEN** no page state SHALL be changed; every page SHALL retain its prior `state`
- **THEN** `TranslationViewModel.errorMessage` SHALL be set to the fixed string `"Failed to clear cache. Translations may still be cached. Please restart the app if the problem persists."`
- **THEN** the SQLite error message SHALL be recorded in `DebugLogger` and SHALL NOT appear in `errorMessage` or any other UI surface

#### Scenario: User cancels clearing
- **WHEN** user dismisses the confirmation alert
- **THEN** no cache data SHALL be modified

### Requirement: Reset page states after clearing
The system SHALL reset all in-memory `MangaPage.state` values to `.pending` after the cache is successfully cleared, so that subsequent translation runs fresh OCR and translation. The reset SHALL NOT occur when the underlying `CacheService.clearAll()` call throws.

#### Scenario: Pages reset after successful cache clear
- **WHEN** cache is cleared successfully while pages are loaded
- **THEN** every page's state SHALL become `.pending`
- **THEN** no automatic re-translation SHALL be triggered

#### Scenario: Pages preserved when cache clear fails
- **WHEN** `CacheService.clearAll()` throws while pages are loaded
- **THEN** no page's state SHALL change

### Requirement: Cache service exposes availability and mutation failure
The system SHALL expose a `CacheService.isAvailable` boolean that is `true` only when the underlying SQLite database has been opened successfully and `PRAGMA foreign_keys = ON` has been executed successfully during initialization. All `CacheService` mutation operations — `store`, `clearAll`, and every `GlossaryService` mutation reached through `CacheService.glossaryService` — SHALL throw a structured error when the operation fails. When `isAvailable` is `false`, mutation operations SHALL throw `CacheError.unavailable` without touching the database. `CacheService.init` SHALL NOT throw; an unusable database SHALL be reported via `isAvailable == false` only.

#### Scenario: Database opens cleanly
- **WHEN** `CacheService.init()` runs and `sqlite3_open_v2` succeeds and `PRAGMA foreign_keys = ON` succeeds
- **THEN** `isAvailable` SHALL be `true`
- **THEN** mutation operations SHALL execute normally and propagate any SQLite error as a thrown `CacheError`

#### Scenario: Database fails to open
- **WHEN** `CacheService.init()` runs and `sqlite3_open_v2` returns a non-success code
- **THEN** `init` SHALL NOT throw and SHALL NOT crash
- **THEN** `isAvailable` SHALL be `false`
- **THEN** every subsequent mutation call SHALL throw `CacheError.unavailable`

#### Scenario: Mutation fails after open succeeded
- **WHEN** `CacheService.clearAll()` is called and `sqlite3_exec` returns a non-success code
- **THEN** `clearAll()` SHALL throw a `CacheError` that carries the SQLite result code and the SQLite error message
- **THEN** `isAvailable` SHALL remain `true` (a single statement failure does not disable the service)

### Requirement: Foreign keys are enforced on every database open
The system SHALL execute `PRAGMA foreign_keys = ON` exactly once, immediately after `sqlite3_open_v2` succeeds during `CacheService.init`. If the pragma fails, the system SHALL close the database handle and set `isAvailable = false`.

#### Scenario: PRAGMA succeeds
- **WHEN** the database is freshly opened and `PRAGMA foreign_keys = ON` executes successfully
- **THEN** `isAvailable` SHALL be `true`
- **THEN** subsequent FK-violating writes (e.g., inserting a `glossary_terms` row whose `glossary_id` has no matching `glossaries` row) SHALL be rejected by SQLite

#### Scenario: PRAGMA fails
- **WHEN** `PRAGMA foreign_keys = ON` returns a non-success code
- **THEN** `CacheService.init` SHALL close the database handle
- **THEN** `isAvailable` SHALL be `false`
- **THEN** every subsequent mutation call SHALL throw `CacheError.unavailable`

### Requirement: Read operations degrade silently when the cache is unavailable
The system SHALL keep read APIs (`lookup`, `translationCacheSize`, `glossaryService.listGlossaries`, `glossaryService.listTerms`) non-throwing. When `isAvailable == false`, these reads SHALL return their documented "nothing found" values rather than throw.

#### Scenario: Lookup on unavailable cache
- **WHEN** `CacheService.lookup(imageHash:, source:, target:, engine:)` is called and `isAvailable == false`
- **THEN** the call SHALL return `nil`
- **THEN** the call SHALL NOT throw

#### Scenario: Glossary list on unavailable cache
- **WHEN** `glossaryService.listGlossaries()` is called and the underlying cache is unavailable
- **THEN** the call SHALL return an empty array
- **THEN** the call SHALL NOT throw

#### Scenario: Cache size on unavailable cache
- **WHEN** `CacheService.translationCacheSize()` is called and `isAvailable == false`
- **THEN** the call SHALL return `0`
- **THEN** the call SHALL NOT throw

### Requirement: SQLite error messages are routed only to the debug log
The system SHALL forward the raw `sqlite3_errmsg` value of any thrown cache error to `DebugLogger` together with the failing operation name. The system SHALL NOT place the raw SQLite message in `TranslationViewModel.errorMessage`, in any `@Published` property exposed to SwiftUI, or in any alert presented to the user.

#### Scenario: Cache clear fails
- **WHEN** `CacheService.clearAll()` throws a `CacheError` whose SQLite message is `"database is locked"`
- **THEN** `DebugLogger` SHALL record an entry containing the operation identifier (e.g., `"CacheService.clearAll"`), the SQLite result code, and the message `"database is locked"`
- **THEN** the UI SHALL NOT display the string `"database is locked"`

### Requirement: Translation pipeline tolerates unavailable cache
The system SHALL allow the translation pipeline to continue when the `CacheService.store` mutation fails or when `isAvailable == false`. Translation results SHALL still be returned to the user even when they cannot be persisted.

#### Scenario: Store fails mid-translation
- **WHEN** the translation pipeline calls `CacheService.store(...)` and the call throws
- **THEN** the pipeline SHALL log the failure to `DebugLogger`
- **THEN** the pipeline SHALL still return the translated page to the user
- **THEN** the page state SHALL transition to `.translated`, not `.error`
