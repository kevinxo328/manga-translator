## Context

Switching the translation engine in the toolbar fires `.onChange(of: translationEngine)` (`ContentView.swift:555-558`), which calls `retranslateCurrentPage()` → `translatePage(at:bypassCache: true)`. The cache key already includes the engine, so a switch back to a previously used engine should be a cache hit; instead the bypass flag forces a fresh API call every time.

The bypass flag cannot simply be flipped to `false` for engine switches, because two behaviors hang off `bypassCache == true` in `preparePage` (`TranslationViewModel.swift:459-596`):

- `:468` — `restoreFrom` backup of the current `.translated` state, used to roll the page back on translation failure.
- `:539` — the bubble-set preservation branch: when the page has a committed non-empty bubble set, reuse it verbatim and skip detection + OCR. This is what keeps user edits (drawn / moved / reordered bubbles) alive across re-translates (see `openspec/specs/retranslate/spec.md`).

With `bypassCache: false`, a cache miss would re-run full OCR (destroying manual bubbles) and a cache hit would overwrite a user-edited layout with the stale cached one.

`finalizePage` already handles `.cacheHit` (`:717-719`), including the recent-context window update, so a cache-hit engine switch can reuse the existing `PagePreparation.cacheHit` path unchanged.

## Goals / Non-Goals

**Goals:**

- Switching to an engine whose result is already cached costs zero API calls and zero OCR.
- All committed user edits (drawn, moved, resized, reordered, deleted bubbles) survive every engine switch, whether the new engine's cache hits or misses.
- The explicit Re-translate button and Re-translate All keep their current bypass-cache semantics.

**Non-Goals:**

- No changes to the batch pipeline (`runBatchPipeline`), Edit Mode Commit, or `CacheService` itself.
- No cache eviction or size accounting (tracked separately as SUGGESTION.md D2).
- No changes to recent-context window semantics — the engine-switch cache hit reuses the existing `.cacheHit` finalize path.

## Decisions

### D1: Replace the `bypassCache` flag with a three-case mode enum

`translatePage(at:bypassCache:)` and `preparePage(at:bypassCache:service:)` take a `PageTranslationMode` enum instead of the bare `Bool`:

- `.standard` — today's `bypassCache: false`: cache lookup, full OCR pipeline on miss.
- `.retranslate` — today's `bypassCache: true`: skip lookup, preserve committed bubbles, re-translate.
- `.engineSwitch` — new: conditional cache lookup (see D2), preserve committed bubbles on miss/mismatch.

**Alternative considered**: a second Bool parameter (`bypassCache` + `allowCacheOnEngineSwitch`). Rejected: produces four combinations of which one is meaningless, and the two flags interact non-obviously inside `preparePage`. An enum names each pipeline shape exactly. `runBatchPipeline` keeps using `.standard` / `.retranslate` only; nothing batch-related changes.

### D2: Cache-hit safety predicate is layout match, not `isManual` presence

The engine-switch mode uses the new engine's cached entry **only when its bubble layout matches the page's committed set**: equal bubble count, and per-bubble equal `boundingBox` (exact `CGRect` equality, no tolerance — same convention as Edit Mode's OCR-dirty rule), equal source `text`, and equal reading-order `index`, comparing both sequences sorted by `index`. Translated text is excluded from the comparison — differing translations are the whole point of the lookup.

On match → display the cached result (no OCR, no API call, no cache write).
On lookup miss or layout mismatch → preserve the committed set verbatim (existing `:539` branch semantics), skip OCR, re-translate only, overwrite the new engine's cache entry on success.

**Alternative considered (and originally proposed in SUGGESTION.md B1)**: gate on "does the committed set contain any `isManual` bubble". Rejected because `isManual` only records *geometry* edits. Reorder-only edits (index changes) and delete-only edits leave `isManual == false` on every surviving bubble, so the predicate would happily restore a stale cached layout that resurrects deleted bubbles or reverts the user's reading order. Commit `c49f813` ("fix(retranslate): preserve manual bubble order") shows order preservation is required behavior, not a nice-to-have. The layout-match predicate subsumes the `isManual` test: a drawn or moved bubble can never match the pre-edit cached layout, so every case the `isManual` test would catch falls out of layout mismatch automatically.

### D3: Pages without a committed non-empty bubble set fall back to `.standard`

If the current page is not `.translated` with a non-empty bubble set (never translated, error-reset, or emptied via Edit Mode), the engine-switch mode behaves exactly like `.standard`: cache lookup first, full OCR pipeline on miss. This is at parity with today for the resurrection edge case — today an engine switch on a `.translated([])` page already re-runs full OCR and resurrects bubbles; the new path may resurrect them from the new engine's cache instead, which is the same user-visible outcome minus the API cost.

### D4: `restoreFrom` semantics carry over to `.engineSwitch`

`.engineSwitch` populates `restoreFrom` the same way `.retranslate` does (`:468`), so a failed translation during an engine switch restores the previous engine's `.translated` state instead of leaving the page in `.error` with lost content.

### D5: UI wiring

The `.onChange(of: translationEngine)` handler in `ContentView` calls a new view-model entry point (`switchEngineForCurrentPage()` → `translatePage(at: currentPageIndex, mode: .engineSwitch)`) instead of `retranslateCurrentPage()`. The existing `!isEditing` guard stays. `retranslateCurrentPage()` / `retranslateAllPages()` are untouched and keep `.retranslate` semantics.

## Risks / Trade-offs

- **[Risk] Layout comparison false negatives** (e.g. float drift in `boundingBox` after cache round-trip would make layouts never match) → `boundingBox` round-trips through `bubbles_json` as exact encoded values and the comparison uses the same no-tolerance equality the Edit Mode commit rule already relies on; a false negative degrades gracefully to today's behavior (one extra API call), never to data loss.
- **[Risk] Stale translations on cache hit** — switching back to engine A shows A's cached translations even if the glossary or prompt context changed since → accepted; identical to every other cache hit in the app. The explicit Re-translate button exists precisely to force a refresh.
- **[Trade-off] Slightly wider surface than SUGGESTION.md B1** — the layout-match predicate is more code than an `isManual` check, but it closes the reorder/delete holes the simpler predicate leaves open; the comparison itself is a pure function over at most a few dozen bubbles.

## Open Questions

(none)
