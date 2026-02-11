## Context

LLM models are hardcoded in `ClaudeTranslationService` (`claude-sonnet-4-5-20250929`) and `OpenAITranslationService` (`gpt-4o-mini`). The settings UI has an API Keys tab with four key inputs and a Preferences tab with language/engine selection. Users want to choose which model to use per provider.

## Goals / Non-Goals

**Goals:**
- Let users select an LLM model for each LLM provider (Claude, OpenAI) from a predefined list
- Show the model picker in the API Keys tab, directly below the corresponding API key input
- Persist model selection across app launches via UserDefaults
- Pass selected model to translation service API calls

**Non-Goals:**
- Custom/arbitrary model name input (predefined list only)
- Model selection for non-LLM engines (DeepL, Google)
- Model-aware cache invalidation (out of scope for now)
- Fetching available models from provider APIs

## Decisions

1. **Model list as enum cases**: Define available models as static arrays on `TranslationEngine` or a new `LLMModel` helper. OpenAI models should be updated to GPT-5 series.

2. **Picker placement**: Place a `Picker` directly below each LLM API key's `SecureField` in the API Keys tab. Add a "Custom..." option to the picker.

3. **Manual Input**: If "Custom..." (or a flag) is selected, show a `TextField` for manual `apiIdentifier` entry. Bind this field to the same `PreferencesService` model property.

3. **PreferencesService storage**: Add `claudeModel` and `openAIModel` properties to `PreferencesService`, persisted via UserDefaults with sensible defaults matching the current hardcoded values.

4. **Service injection**: Translation services already receive `KeychainService`. Add the model string parameter to the service initializer or make them read from `PreferencesService`. Since services are created in `TranslationViewModel.translationService`, pass the model there.

## Risks / Trade-offs

- **Stale model list**: The predefined list will become outdated as providers release new models. Mitigation: keep the list easy to update in one place; a future enhancement could fetch models from APIs.
- **Cache confusion**: Changing models doesn't invalidate cache. Users may see translations from a previous model. Acceptable for now — cache is already keyed by engine, and users can clear cache manually.
