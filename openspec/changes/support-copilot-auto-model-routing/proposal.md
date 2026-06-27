## Why

GitHub changed Copilot Free and Student plans on 2026-06-24 so Auto is their only model-selection path. MangaTranslator currently treats `auto` as a concrete model identifier and sends it directly to `/chat/completions`, which GitHub rejects with `model_not_supported`; it also cannot distinguish models that support `/chat/completions` from models restricted to `/responses`.

## What Changes

- Represent Copilot model transport capabilities from the `/models` response, including `supported_endpoints`, separately from model-picker visibility.
- Resolve Auto through the Copilot model-session protocol before translation, use the returned concrete `selected_model`, and attach the returned `Copilot-Session-Token` to inference requests.
- Restrict Auto model hints to models that support MangaTranslator's implemented `/chat/completions` transport; do not guess capability from model names.
- Cache and refresh the short-lived Auto session safely across single-page and batch translations. Refresh uses the still-valid old `Copilot-Session-Token` on the same host/account/hint key, falls back to one headerless acquisition after refresh 401, and shares one bounded recovery budget for protocol-specific inference failures.
- Cache successful model catalogs for five minutes with account/host isolation and single-flight fetching so Settings and translation share capability data without making Settings a prerequisite.
- Preserve explicit model selection for accounts that expose picker-enabled models while presenting a fixed Auto state for Auto-only accounts.
- Distinguish Settings loading, Auto-only, selectable, no-compatible-model, and request-failure states instead of collapsing all failures into an empty model list.
- Change the first-launch Copilot preference to `auto` and migrate an unavailable saved model to Auto only when Auto is usable.
- Add sanitized operational logging for the resolved concrete model without logging OAuth or Copilot session tokens.
- Specify and implement the change through vertical TDD slices: one failing behavior test, minimal implementation, then the next slice; refactoring occurs only after all slices are green.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `copilot-model-management`: Add transport-capability discovery, Auto-only versus selectable account presentation, explicit loading/error states, and Auto preference migration behavior.
- `translation-service`: Replace direct `model: "auto"` inference with the Copilot Auto model-session handshake, concrete-model validation, session-token propagation, caching, refresh, endpoint fallback, and bounded recovery behavior.

## Impact

- Affected production code: `MangaTranslator/Models/Models.swift`, `MangaTranslator/Services/CopilotEnvironment.swift`, `MangaTranslator/Services/CopilotTranslationService.swift`, `MangaTranslator/Services/ChatCompletionsClient.swift`, `MangaTranslator/Services/PreferencesService.swift`, `MangaTranslator/Views/SettingsView.swift`, plus focused process-local actors for model-catalog and Auto-session state.
- Affected tests: `MangaTranslatorTests/CopilotEnvironmentTests.swift`, `MangaTranslatorTests/CopilotTranslationServiceTests.swift`, `MangaTranslatorTests/PreferencesServiceTests.swift`, and Settings/SwiftUI correctness tests.
- External protocol: private GitHub Copilot endpoints `/models`, `/models/session`, and `/chat/completions`, with `X-GitHub-Api-Version: 2026-07-01` for model-session-aware Copilot requests. This contract is not a public stable API and must remain isolated behind the Copilot service boundary.
- No new package dependency or entitlement is required. Existing OAuth tokens remain Keychain-only; the short-lived session token remains memory-only.
