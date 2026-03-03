## Why

Current translation is stateless: each page is translated in isolation without knowledge of prior pages or consistent terminology. This results in inconsistent proper noun rendering (character names, technique names) and dialogue that lacks narrative continuity across pages.

## What Changes

- Introduce a glossary system: named, user-managed term tables stored in SQLite, selectable per session
- LLM translation prompts now include active glossary terms and a rolling summary of recent pages
- LLM auto-detects new proper nouns during translation and proposes them as glossary additions
- Users can create, rename, delete glossaries, and add/edit/delete individual terms
- A glossary picker in the main UI lets users choose which glossary to apply before translating

## Capabilities

### New Capabilities

- `glossary-management`: Named glossary tables (SQLite-backed), CRUD for glossaries and individual terms, auto-detection of proper nouns by LLM, user-facing management sheet UI
- `contextual-translation`: Rolling in-memory window of recent page translations injected into LLM prompts for cross-page narrative continuity

### Modified Capabilities

- `translation-service`: LLM prompt construction now accepts glossary terms and recent-page context; response parsing extended to extract `detected_terms`

## Impact

- **New files**: `GlossaryService.swift`, `GlossaryView.swift`
- **Modified files**: `CacheService.swift` (new tables), `LLMPrompt.swift` (glossary + context injection), `ClaudeTranslationService.swift`, `OpenAITranslationService.swift` (pass glossary/context), `TranslationViewModel.swift` (session state for glossary + rolling context), `ContentView.swift` (glossary picker/button)
- **Database**: Two new SQLite tables (`glossaries`, `glossary_terms`) added to existing `cache.sqlite`
- **No new external dependencies**
