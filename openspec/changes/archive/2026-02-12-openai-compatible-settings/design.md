## Context

The app currently hardcodes the OpenAI API endpoint to `https://api.openai.com/v1/chat/completions` in `OpenAITranslationService.swift`. The settings UI shows an "OpenAI" section with an API key field and a model picker (dropdown with preset models + custom option). Users who want to use OpenAI-compatible providers (local LLMs, Azure OpenAI, etc.) cannot do so without code changes.

Key files:
- `SettingsView.swift` — OpenAI section UI with API key and model picker
- `PreferencesService.swift` — persists `openAIModel` in UserDefaults (default: `gpt-4o-mini`)
- `OpenAITranslationService.swift` — hardcoded URL to `api.openai.com`
- `Models.swift` — `TranslationEngine.openAI` display name and `openAIModels` list
- `TranslationViewModel.swift` — creates `OpenAITranslationService` with model param

## Goals / Non-Goals

**Goals:**
- Allow users to configure a custom base URL for any OpenAI-compatible API
- Simplify model selection to a free-text field with a sensible default (`gpt-5`)
- Provide "Reset to Default" buttons for both base URL and model fields
- Validate inputs to prevent common mistakes (trailing slash in URL, leading slash in model)
- Rename the UI section and engine display name to "OpenAI Compatible"

**Non-Goals:**
- Supporting non-OpenAI-compatible API formats (different request/response schemas)
- Connection testing or URL validation beyond basic sanitization
- Changing the Claude section or any other translation engine

## Decisions

### 1. Free-text fields instead of Picker for model selection

**Choice**: Replace the `Picker` + "Custom..." option with a single `TextField` pre-filled with the default model.

**Rationale**: Since users of compatible APIs will use arbitrary model names, a picker with OpenAI-specific models adds no value. A simple text field is more flexible and requires less code.

**Alternative considered**: Keep the picker and add a separate "compatible mode" toggle — rejected as unnecessarily complex.

### 2. Base URL stored without trailing path components

**Choice**: Store the base URL as the root (e.g., `https://api.openai.com/v1`) and append `/chat/completions` in the service code.

**Rationale**: Most OpenAI-compatible APIs document their base URL as ending with `/v1`. Appending the endpoint path in code keeps the user input clean and consistent.

### 3. Input sanitization approach

**Choice**: Silently strip trailing `/` from base URL and leading `/` from model name when saving/using values, rather than showing validation errors.

**Rationale**: These are common copy-paste mistakes. Silent correction provides better UX than error messages. The sanitization happens at the service layer when constructing the request URL.

### 4. Default values as constants

**Choice**: Define default base URL (`https://api.openai.com/v1`) and default model (`gpt-5`) as static constants on `PreferencesService` or a shared location.

**Rationale**: Single source of truth for reset buttons and initial values. Avoids magic strings scattered across files.

## Risks / Trade-offs

- **[Breaking display name change]** → Low risk. Only affects the UI label and engine picker text. No data migration needed since `TranslationEngine.rawValue` ("openai") stays the same.
- **[Default model change from gpt-4o-mini to gpt-5]** → Existing users with the old default will keep their stored value. Only new installs get `gpt-5`. No migration needed.
- **[Invalid base URLs]** → Users could enter non-URL strings. Mitigation: the service will fail gracefully with the existing error handling when the URL is invalid. No extra validation needed beyond slash stripping.
