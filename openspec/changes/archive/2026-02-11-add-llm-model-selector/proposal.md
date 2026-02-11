## Why

LLM model names are currently hardcoded in translation services (`claude-sonnet-4-5-20250929` for Claude, `gpt-4o-mini` for OpenAI). Users cannot choose which model to use without modifying source code. Adding a model selector lets users pick models based on their quality/cost/speed preferences, and makes it easy to adopt new models as they're released.

## What Changes

- Add an LLM model selector UI in the API Keys tab of SettingsView, displayed below each LLM provider's API key input (OpenAI and Claude)
- Support manual model identifier entry for power users or unlisted models
- Update predefined OpenAI models to GPT-5 series
- Add model preference persistence via UserDefaults in PreferencesService
- Pass the selected model to LLM translation services instead of using hardcoded values

## Capabilities

### New Capabilities
- `llm-model-selection`: User-facing model selection for LLM-based translation engines (OpenAI and Claude), with persistence and integration into the translation pipeline

### Modified Capabilities

## Impact

- **UI**: SettingsView API Keys tab gains model picker controls for OpenAI and Claude
- **Services**: ClaudeTranslationService and OpenAITranslationService read model from preferences instead of hardcoded strings
- **Persistence**: PreferencesService adds new UserDefaults keys for model selection
- **Cache**: Existing translation cache keyed by engine remains valid (model change doesn't affect cache key, but users should be aware cached results may come from a different model)
