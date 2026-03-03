## Context

Manga Translator currently translates each page in complete isolation. Every LLM call receives only the current page's OCR text with no knowledge of prior pages or established terminology. This produces two classes of quality failures: (1) inconsistent proper noun rendering—the same character name may be romanised differently across pages—and (2) dialogue that reads as disconnected because the LLM cannot infer narrative continuity from the previous page.

The app already stores translations in a SQLite cache (`cache.sqlite`). All API keys are in Keychain. The LLM prompt is assembled in `LLMPrompt.swift` and consumed by `ClaudeTranslationService` and `OpenAITranslationService`. Session state lives in `TranslationViewModel`.

## Goals / Non-Goals

**Goals:**
- Named, user-managed glossaries stored persistently in SQLite
- Glossary terms injected into LLM system prompts at translation time
- LLM auto-detection of new proper nouns returned alongside translations (no extra API round-trip)
- A rolling in-memory window of recent page translations injected as narrative context
- A glossary management sheet in the main UI (create, rename, delete glossaries; add, edit, delete terms)

**Non-Goals:**
- Improving DeepL / Google translation quality beyond a post-processing term-substitution pass (out of scope for v1)
- Persisting the cross-page rolling context across app restarts
- Vector/embedding-based term retrieval (unnecessary at expected glossary sizes < 500 terms)
- Automatic glossary assignment based on folder or file path

## Decisions

### D1: Store glossaries in existing `cache.sqlite`, not a new file
**Rationale:** Avoids a second database handle, migration logic, and user-facing file management. The cache is already at a known path (`~/Library/Application Support/MangaTranslator/cache.sqlite`). Glossary data is small and relational, making SQLite appropriate.
**Alternative considered:** A separate `glossary.sqlite` — rejected because it adds operational complexity with no benefit.

### D2: Auto-detect terms via extended JSON response, not a separate LLM call
**Rationale:** Asking the LLM to return `detected_terms` alongside `translation` in the same response adds zero latency and zero API cost. A separate "extraction" call would double the cost of every LLM translation.
**Alternative considered:** A post-hoc extraction prompt — rejected due to cost and latency.

### D3: Rolling window limited to the last 3 pages, stored in-memory only
**Rationale:** Three pages is enough narrative context for dialogue continuity; more risks exceeding token budgets on long-page manga. In-memory keeps the implementation simple and avoids stale context across reading sessions.
**Alternative considered:** Persisted context — rejected because context from a prior session is likely to mislead rather than help.

### D4: Glossary UI as a modal sheet, not a new sidebar section
**Rationale:** Glossary management is an occasional task (not per-page). A sheet keeps it off the critical path and avoids cluttering the sidebar that users interact with constantly. A toolbar button gives easy access when needed.
**Alternative considered:** A new sidebar tab — rejected because it competes visually with the translation card list.

### D5: Glossary selection is manual and per-session (not auto-assigned)
**Rationale:** The app has no persistent concept of a "manga project". Auto-assigning by folder path would break for users who reorganise files. Making it a deliberate, lightweight choice avoids wrong-glossary surprises.
**Alternative considered:** Auto-assign by folder path — rejected due to fragility and the app's stateless file-loading model.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Large glossaries inflate token count and cost | Cap injection at 100 terms per call; surface term count in the UI |
| LLM ignores glossary instructions | Prompt uses imperative "MUST follow exactly" wording; user can always manually correct via the glossary editor |
| `detected_terms` contains noise (common words mistaken for proper nouns) | Mark as "auto-detected" and require user confirmation before terms affect future translations (auto-detected terms are injected but flagged) |
| SQLite schema migration on existing installs | Use `CREATE TABLE IF NOT EXISTS`; no column changes to existing tables |

## Open Questions

- Should auto-detected terms be injected immediately (same session) or only after user confirms them? Current design injects immediately but flags them as unconfirmed. If this causes quality regressions, we can gate injection on confirmation.
