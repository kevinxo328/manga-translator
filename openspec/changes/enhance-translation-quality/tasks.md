## 1. Database Schema

- [ ] 1.1 Add `glossaries` table creation to `CacheService.swift` using `CREATE TABLE IF NOT EXISTS`
- [ ] 1.2 Add `glossary_terms` table creation to `CacheService.swift` using `CREATE TABLE IF NOT EXISTS`

## 2. GlossaryService

- [ ] 2.1 Create `GlossaryService.swift` with CRUD for glossaries (create, list, delete)
- [ ] 2.2 Add CRUD for terms (insert, update, delete, list by glossary)
- [ ] 2.3 Add method to insert auto-detected terms (skipping duplicates by source_term)
- [ ] 2.4 Add method to fetch all terms for a glossary (used for prompt injection)

## 3. LLM Prompt Enhancement

- [ ] 3.1 Update `LLMPrompt.swift` to accept optional glossary terms array and inject as "## Glossary (MUST follow exactly)" section in system prompt
- [ ] 3.2 Update `LLMPrompt.swift` to accept optional recent-page context array and inject as "## Recent context (previous pages)" section
- [ ] 3.3 Extend expected JSON response format comment/documentation to include optional `detected_terms` field
- [ ] 3.4 Update response parsing in `ClaudeTranslationService.swift` to extract `detected_terms` from the response
- [ ] 3.5 Update response parsing in `OpenAITranslationService.swift` to extract `detected_terms` from the response

## 4. Translation Service Wiring

- [ ] 4.1 Update `ClaudeTranslationService.swift` to accept glossary terms and recent context, pass to prompt builder
- [ ] 4.2 Update `OpenAITranslationService.swift` to accept glossary terms and recent context, pass to prompt builder
- [ ] 4.3 Update `TranslationService` protocol (if needed) to include glossary and context parameters

## 5. Session State in TranslationViewModel

- [ ] 5.1 Add `activeGlossaryID: String?` property to `TranslationViewModel`
- [ ] 5.2 Add `recentPageTranslations: [String]` rolling window (max 3) to `TranslationViewModel`
- [ ] 5.3 After each page translation, append translated text to rolling window (dropping oldest if > 3)
- [ ] 5.4 Reset rolling window when a new image set is loaded
- [ ] 5.5 Pass active glossary terms and rolling context to translation service calls
- [ ] 5.6 After translation, call `GlossaryService` to write auto-detected terms to active glossary

## 6. Glossary UI

- [ ] 6.1 Create `GlossaryView.swift` as a modal sheet with glossary picker (top), term list (middle), add-term button (bottom)
- [ ] 6.2 Implement glossary list/create/delete in `GlossaryView`
- [ ] 6.3 Implement term list with source, target, and auto-detected badge per row
- [ ] 6.4 Implement inline/edit flow for adding and editing terms
- [ ] 6.5 Implement swipe-to-delete for individual terms
- [ ] 6.6 Add "Delete Glossary" action with confirmation alert

## 7. Main UI Integration

- [ ] 7.1 Add a "Glossary" toolbar button to `ContentView.swift` that opens `GlossaryView` as a sheet
- [ ] 7.2 Add glossary picker (dropdown/menu) in the toolbar or sidebar header showing active glossary name or "None"
- [ ] 7.3 Wire glossary picker selection to `TranslationViewModel.activeGlossaryID`
