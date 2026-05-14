## Why

The translation pipeline always runs OCR even when no translation is needed, and passes punctuation-only OCR results through to both the translation engine and the sidebar. These unnecessary operations waste API credits, slow down processing, and clutter the sidebar with meaningless entries. The fix is cheap: check early, log why, and stop.

## What Changes

- When source language equals target language, OCR is skipped entirely — no network call, no model inference, page state set to `.translated([])` immediately.
- After OCR completes, bubbles whose text is empty or consists entirely of punctuation/whitespace are filtered out before translation. They do not appear in the sidebar.
- A new `.pipeline` log category is added to `DebugLogCategory` for skip-decision events.
- Each skip decision (same-language bypass, meaningless-bubble filter) emits a log entry at `.pipeline` category with a `metadata` dictionary carrying the reason and relevant counts or language values.
- The `needsTranslation` intermediate variable and the redundant post-OCR `sourceLanguage == targetLanguage` branch are removed.

## Capabilities

### New Capabilities

- `pipeline-skip-optimization`: Rules for when the OCR and translation steps are bypassed, what constitutes a "meaningless" bubble, and what gets logged at each decision point.

### Modified Capabilities

- `debug-log-management`: New `.pipeline` log category is added alongside existing categories; skip-decision events must be visible in the debug log view.

## Impact

- **`TranslationViewModel.swift`** — `translatePage(at:bypassCache:)` restructured; early-exit guard added before OCR; post-OCR filter replaces passthrough logic.
- **`DebugLogger.swift`** — `DebugLogCategory` gains `.pipeline` case.
- **`MangaTranslatorTests/TranslationViewModelTests.swift`** — new test file covering same-language skip, empty-OCR skip, punct-only filter, and mixed-bubble filter.
- No changes to translation service protocols, OCR engines, cache keys, or UI beyond sidebar showing fewer (correct) entries.
