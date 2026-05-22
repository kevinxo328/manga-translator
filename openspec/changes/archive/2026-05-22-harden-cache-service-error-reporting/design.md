## Context

`CacheService` owns the single SQLite database that backs translation cache, file-open history, and glossaries. Its `init` opens the database with `sqlite3_open_v2`; any failure currently writes a log line and stores a `nil` handle while still vending a usable-looking instance. Subsequent calls (`store`, `addHistory`, `clearAll`, glossary mutations) ignore the result of `sqlite3_exec` / `sqlite3_step` and return `Void`. The cache-management spec already requires that lookups return `nil` after `clearAll()`, but it does not yet describe what happens when the operation itself fails.

The blast radius is small but the failures it hides are concrete:
- `TranslationViewModel.clearCacheAndResetPages()` resets every page to `.pending` even when `DELETE FROM translation_cache` failed, so the user re-translates work that the cache still contains.
- `GlossaryService.deleteGlossary` issues two unguarded `DELETE` statements (terms first, then the glossary). A failure between them leaves terms without a parent, or a glossary with stale terms.
- The schema declares `FOREIGN KEY (glossary_id) REFERENCES glossaries(id)` but `PRAGMA foreign_keys = ON` is never executed, so the FK is informational only.

Production call sites are limited (`TranslationViewModel` plus a handful of glossary UI handlers). Tests live in `MangaTranslatorTests/CacheServiceTests.swift` and `MangaTranslatorTests/TranslationViewModelTests.swift`. There is no SwiftUI preview that constructs `CacheService`.

## Goals / Non-Goals

**Goals:**
- Make every `CacheService` and `GlossaryService` mutation failure visible to the caller without changing how reads behave on a healthy database.
- Preserve translation-pipeline behaviour when the cache is unavailable: translation must continue, just without caching.
- Guarantee that `GlossaryService.deleteGlossary` is atomic — either both `glossary_terms` and `glossaries` rows are gone, or neither is.
- Enforce the existing `FOREIGN KEY` declaration at runtime by enabling `PRAGMA foreign_keys = ON`.
- Keep raw SQLite error strings out of the UI; route them to `DebugLogger`.

**Non-Goals:**
- No schema migration. We do not rewrite tables, add `ON DELETE CASCADE`, or otherwise change column layout.
- No change to cache keys, table names, or serialized payload format.
- No proactive startup alert when the database is unavailable. The UI only learns about the failure when the user attempts a mutation.
- No persistent UI banner. The existing one-shot `errorMessage` alert is sufficient.
- No sanitizer pipeline for cache errors. Generic UI strings are hard-coded; sanitization belongs to Task 6.
- No changes to archive import, OCR, model lifecycle, or translation provider services.

## Decisions

### Decision 1: Error strategy — keep `init` non-throwing; add `isAvailable`; mutations throw

`CacheService.init()` keeps its current `Void` return. We add a `let isAvailable: Bool` property that is `true` only when `sqlite3_open_v2` succeeded **and** `PRAGMA foreign_keys = ON` succeeded. Mutation APIs become `throws`; read APIs do not.

**Alternatives considered:**
- `init throws`: cleanest semantics (an instance is guaranteed usable), but every construction site — including SwiftUI previews and future call sites — would need `try`/`do`. Adds ceremony to a failure mode that, on macOS, is rare enough that "best-effort instance with a flag" is the better default.
- `init throws` + `try?` factory fallback: combines complexity of both approaches without removing either downside.

**Rationale:** keeping `init` non-throwing limits the diff to the four production mutation sites in `TranslationViewModel` and the glossary UI handlers. Read code does not change at all. The `isAvailable` flag gives diagnostic surfaces a single source of truth without forcing every caller to inspect it.

### Decision 2: Read APIs degrade silently to `nil` / `[]` / `0`

When `isAvailable == false`, `lookup` returns `nil`, `glossaryService.listGlossaries()` returns `[]`, and `translationCacheSize()` returns `0`. They do not throw.

**Alternatives considered:**
- Reads also throw: forces error handling in every cache-miss path, which already returns `nil` for legitimate misses. The two cases would then become indistinguishable from the caller's perspective without inspecting the error.
- Reads throw but reads from a fresh process return `nil`: brittle, depends on instance lifetime.

**Rationale:** `nil` from `lookup` already means "no cached translation, run the full pipeline." Treating database unavailability as a permanent cache miss preserves correctness in the translation flow at zero call-site cost.

### Decision 3: UI notification reuses `TranslationViewModel.errorMessage`

The existing `@Published var errorMessage: String?` already drives a `.alert` modal in `ContentView`. We reuse it for cache failures rather than introducing a banner or new alert binding.

**Alternatives considered:**
- New `cacheUnavailable` published property + persistent banner: adds a SwiftUI element, a new `@Published` property, and `ContentView` plumbing. Disproportionate for a rare condition.
- Toast / transient overlay: project has no toast infrastructure; building one is out of scope.

**Rationale:** the existing modal is the same UX `loadFiles` archive failures already use. Users see a familiar pattern, no new UI is added.

### Decision 4: No proactive startup alert

We do not check `isAvailable` from `TranslationViewModel.init` and we do not raise an alert when the app launches with an unusable cache. The user only sees an error when they attempt a mutation that fails (`clearCacheAndResetPages`, glossary edits).

**Alternatives considered:**
- Startup alert on `isAvailable == false`: nothing actionable is shown ("cache unavailable" doesn't tell the user what to do), and the alert blocks the app at launch even though translation still works.
- Persistent badge in Settings: requires new UI, out of scope.

**Rationale:** the failure is rare and recoverable (restart, repair disk). Until the user actually tries to clear or edit, they are not affected. Surfacing failure exactly when it blocks a user action keeps the message contextual.

### Decision 5: Generic UI message; SQLite text only to `DebugLogger`

`TranslationViewModel.clearCacheAndResetPages` sets `errorMessage` to a fixed string:
```
Failed to clear cache. Translations may still be cached. Please restart the app if the problem persists.
```
The underlying `sqlite3_errmsg` string is forwarded to `DebugLogger` along with the operation name. The same pattern applies to glossary edit failures, where the message is:
```
Failed to update glossary. Please try again, or restart the app if the problem persists.
```

**Alternatives considered:**
- Embed the SQLite message in the UI: SQLite messages today are safe (no PII, no tokens), but the contract is implicit. A future SQLite version or pragma change could surface paths or sensitive content.
- Use Task 6's sanitizer: cache errors are not network responses, so the sanitizer adds shape without removing risk.

**Rationale:** fixed strings keep the UI stable, predictable, and free of values that depend on database internals. Operators with access to debug logs still get the underlying message.

### Decision 6: Glossary delete becomes transactional; schema is not changed

`GlossaryService.deleteGlossary` wraps both deletes in `BEGIN IMMEDIATE` / `COMMIT`, with `ROLLBACK` on any error. The FOREIGN KEY clause stays as-is (`REFERENCES glossaries(id)`, no `ON DELETE CASCADE`). No migration is written.

**Alternatives considered:**
- Add `ON DELETE CASCADE` and write a migration: `CREATE TABLE IF NOT EXISTS` does not retro-apply, so we would need a destructive `CREATE NEW → COPY → DROP → RENAME` sequence on user databases. The migration would have to run on every launch and risks corrupting existing glossary data.
- Add `ON DELETE CASCADE` for new installs only: produces two divergent schemas in the wild, requiring future code to handle both.

**Rationale:** the real failure mode is "two unguarded DELETEs," and a transaction fixes it without touching user data. `PRAGMA foreign_keys = ON` is still enabled so future inserts/deletes that violate the FK are rejected at runtime.

### Decision 7: `PRAGMA foreign_keys = ON` runs once on open; failure marks service unavailable

After `sqlite3_open_v2` succeeds, `init` executes `PRAGMA foreign_keys = ON`. If that fails, `init` closes the handle and sets `isAvailable = false`, identical to an open failure. This treats FK enforcement as part of the contract — without it, the FK clause is decorative.

**Alternatives considered:**
- Best-effort PRAGMA (log on failure but treat service as available): leaves the FK silently disabled, which is the current bug. Not acceptable.
- Re-enable PRAGMA per-connection: SQLite connection in this codebase is single-instance, so there is no per-connection retry surface.

## Risks / Trade-offs

- **Risk**: existing user databases already contain orphan `glossary_terms` rows from prior unguarded deletes. → **Mitigation**: enabling `PRAGMA foreign_keys = ON` only checks new mutations, not existing rows, so legacy orphans remain but are no longer created. A future cleanup change can purge them; out of scope here.
- **Risk**: `BEGIN IMMEDIATE` in `deleteGlossary` can fail with `SQLITE_BUSY` if another writer holds the database. → **Mitigation**: throw the SQLite error to the caller, which surfaces the generic UI message and logs the busy error. No retry loop is added — the cache is single-writer in practice (one `CacheService` instance per app process).
- **Risk**: `addHistory` and `store` failures during translation are silenced (only logged), so cache regressions could go unnoticed. → **Mitigation**: tests assert that translation continues but `DebugLogger` records the failure. Diagnostic dashboards can flag rate spikes.
- **Trade-off**: the generic UI message hides root cause from end users. Operators must read debug logs to diagnose. This is acceptable because cache failures on macOS are typically environmental (full disk, permissions) and the restart guidance covers the common path.
- **Trade-off**: keeping `init` non-throwing means every mutation site must remember to `try`. The compiler enforces this for new code; existing call sites are migrated explicitly in this change.

## Migration Plan

No database migration is needed. Schema is unchanged.

Code migration is mechanical and bounded:
1. Add `CacheError` enum and `isAvailable` flag to `CacheService`.
2. Convert `CacheService` mutations to `throws`; convert `GlossaryService` mutations to `throws`; wrap `deleteGlossary` in a transaction.
3. Enable `PRAGMA foreign_keys = ON` in `init`.
4. Add `try`/`try?` at the four `TranslationViewModel` mutation sites and the glossary UI handlers.
5. Update `clearCacheAndResetPages` to preserve page state on failure and set `errorMessage`.
6. Update tests to assert the new contract.

Rollback is a single revert; no data is rewritten so no rollback migration is needed.
