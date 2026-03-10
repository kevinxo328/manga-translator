## Why

The Claude API integration is being removed to simplify the translation service architecture and focus on the most commonly used providers: DeepL, Google Translate, and OpenAI Compatible APIs. Maintaining the Claude-specific implementation is no longer prioritized.

## What Changes

- Remove `ClaudeTranslationService.swift` and all associated logic.
- Remove Claude-related configuration options from the Settings view.
- Remove Claude from the available translation service selection in the UI.
- Update internal routing and model selection to exclude Claude. **BREAKING**

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `translation-service`: Remove Claude as a supported translation provider and update the service discovery/routing logic.
- `llm-model-selection`: Remove Claude models (e.g., Claude 3.5 Sonnet) from the selection list.
- `settings-management`: Remove API key and configuration fields specifically for Claude.

## Impact

- **Affected Code**: `MangaTranslator/Services/ClaudeTranslationService.swift` (deletion), `MangaTranslator/Views/SettingsView.swift`, `MangaTranslator/Services/TranslationViewModel.swift`.
- **APIs**: The internal translation service interface will no longer accept Claude-specific parameters.
- **Dependencies**: Potential removal of any Claude-specific SDKs if applicable (though currently implementation seems to be direct REST).
