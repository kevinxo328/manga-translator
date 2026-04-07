# Design: GitHub Copilot Engine

## Architecture

### New Files
- `MangaTranslator/Services/CopilotEnvironment.swift` — availability check + model fetching
- `MangaTranslator/Services/CopilotTranslationService.swift` — `TranslationService` conformance

### Modified Files
- `MangaTranslator/Models/Models.swift` — add `.githubCopilot` case to `TranslationEngine`
- `MangaTranslator/Services/PreferencesService.swift` — add `copilotModel: String`
- `MangaTranslator/ViewModels/TranslationViewModel.swift` — handle `.githubCopilot` in `translationService`; skip `hasKey` check for Copilot
- `MangaTranslator/Views/SettingsView.swift` — add Copilot section in API Keys tab; hide engine option when unavailable

## Key Decisions

### Token retrieval
`CopilotEnvironment` reads directly from macOS keychain (`kSecAttrService = "copilot-cli"`) without account filter. This is a read-only access to the Copilot CLI's stored `gho_` OAuth token. Token is not cached — re-read per translation call to handle expiry.

### API endpoint
`https://api.individual.githubcopilot.com/chat/completions` with headers:
- `Authorization: Bearer <gho_token>`
- `Copilot-Integration-Id: copilot-developer-cli`

### Availability check
`CopilotEnvironment.check() -> CopilotAvailability` runs synchronously:
1. Spawns `Process` calling `/usr/bin/which copilot` → `.notInstalled` if exit ≠ 0
2. Reads keychain entry → `.notLoggedIn` if missing
3. Returns `.available(token:)` otherwise

### hasKey bypass in TranslationViewModel
`translatePage(at:)` guards on `keychainService.hasKey(for: engine)`. For `.githubCopilot` this is always false (no app-owned key). Guard is updated to skip the check for Copilot; the service itself throws `missingAPIKey` at runtime if unavailable.

### Engine picker filtering
`SettingsView` loads `CopilotAvailability` on `.task`. Engine picker renders only available engines — Copilot is filtered out when `copilotAvailability != .available`.

### Model list
Fetched asynchronously via `CopilotEnvironment.fetchModels(token:)` when Copilot section appears. Filters out `text-embedding-*` models. Stored selection in `PreferencesService.copilotModel` (default: `gpt-5-mini`).
