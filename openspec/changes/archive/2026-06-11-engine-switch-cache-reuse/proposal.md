## Why

Switching the translation engine in the toolbar auto-triggers `retranslateCurrentPage()`, which hard-codes `bypassCache: true`. The cache key already includes the engine (image hash + source + target + engine), so switching back to an engine whose result is already cached should be a free cache hit — instead the app pays a redundant API call (and waits on it) every time the user flips engines to compare translations.

## What Changes

- Engine switching gets a dedicated translation mode instead of reusing the Re-translate path:
  - Look up the new engine's cache first. If the cached entry's bubble layout matches the page's committed set (same count; per-bubble equal `boundingBox`, source `text`, and `index`), use the cached result directly — no OCR, no API call, no cache write.
  - On a cache miss, or when the cached layout differs from the committed set (manual bubbles drawn, geometry moved, bubbles deleted, or reading order changed since that entry was written), preserve the committed bubble set verbatim, skip OCR, re-run translation only, and overwrite the new engine's cache entry. (Layout match rather than an `isManual` test, because reorder-only and delete-only edits never flip `isManual` — see design.md D2.)
  - Pages with no committed non-empty bubble set fall back to the standard path: cache lookup, full OCR on miss.
- The explicit Re-translate button and Re-translate All keep `bypassCache: true` semantics unchanged.
- `openspec/specs/retranslate/spec.md` is updated: the bypass-cache requirement is narrowed to explicit Re-translate actions, and a new engine-switch requirement is added.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `retranslate`: Narrow the "bypassing cache lookup" requirement to the explicit Re-translate button / Re-translate All actions; rewrite the "(or the engine-change auto-triggers re-translate)" parenthetical in the "Re-translate with different engine preserves edits" scenario to point at the new requirement; add a new "Engine switch reuses per-engine cache" requirement covering matching cache hit, cache miss, manual-edit mismatch, reorder-only mismatch, untranslated page, and translation failure.

## Impact

- `MangaTranslator/ViewModels/TranslationViewModel.swift`: `translatePage(at:bypassCache:)` / `preparePage` gain an engine-switch mode (e.g. a `TranslationMode` enum replacing the bare `bypassCache` flag on this path); `retranslateCurrentPage()` stays bypass for the button path.
- `MangaTranslator/Views/ContentView.swift:555-558`: the `.onChange(of: translationEngine)` handler calls the new engine-switch entry point instead of `retranslateCurrentPage()`.
- `MangaTranslatorTests`: new tests covering manual-bubble survival across engine switches, cache-hit-no-API on engine switch, and cache-miss-preserves-bubbles; existing re-translate tests remain valid.
- No changes to `CacheService`, `manual-bubble-editing`, or the Edit Mode Commit path.
