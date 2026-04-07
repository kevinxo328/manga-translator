## Why

Users who have a GitHub Copilot subscription can access a wide range of LLM models (GPT-5, Claude, Gemini) through the Copilot API without needing separate API keys. Adding GitHub Copilot as a translation engine lets these users translate manga at no extra cost using their existing subscription.

## What Changes

- Add `githubCopilot` case to `TranslationEngine` enum
- Add `CopilotEnvironment` availability check (verifies `copilot` binary and keychain token at launch and settings open)
- Add `CopilotTranslationService` that calls `https://api.individual.githubcopilot.com/chat/completions` using the Copilot CLI's stored OAuth token
- Add dynamic model list fetching from `https://api.individual.githubcopilot.com/models` (filters out embedding models)
- Add `copilotModel` preference to `PreferencesService`
- Extend Settings UI: GitHub Copilot section with availability status indicator and dynamic model picker
- Extend `KeychainService` with a read-only method to retrieve the Copilot CLI's stored `gho_` OAuth token

## Capabilities

### New Capabilities
- `github-copilot-engine`: GitHub Copilot translation backend with local CLI availability check, OAuth token retrieval from keychain, dynamic model list, and OpenAI-compatible chat completions integration

### Modified Capabilities
- `translation-service`: New `githubCopilot` backend conforming to `TranslationService` protocol
- `settings-management`: New GitHub Copilot section in Settings; engine option is disabled when CLI not installed or not logged in
- `llm-model-selection`: Extended to support dynamic model list fetched from Copilot API (vs. static list for OpenAI Compatible)

## Impact

- `Models.swift`: New `TranslationEngine` case
- `KeychainService.swift`: New method to read external keychain entry (service: `copilot-cli`)
- `PreferencesService.swift`: New `copilotModel` property
- `SettingsView.swift`: New Copilot section with availability status and model picker
- `TranslationViewModel.swift`: Handle new engine case when building `TranslationService`
- New files: `CopilotTranslationService.swift`, `CopilotEnvironment.swift`
- No new dependencies; uses `Security` framework (already imported) and `Foundation.Process` for binary check
