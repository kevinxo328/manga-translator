## Why

The current OpenAI integration is hardcoded to `api.openai.com`. Many users use OpenAI-compatible APIs (e.g., local LLMs, Azure OpenAI, or other providers that implement the same `/v1/chat/completions` endpoint). Renaming the section to "OpenAI Compatible" and adding a configurable base URL enables these use cases without any additional translation service code.

## What Changes

- **BREAKING**: Rename the "OpenAI" settings section header to "OpenAI Compatible"
- Update the `TranslationEngine.openAI` display name from "OpenAI" to "OpenAI Compatible"
- Add a **Base URL** text field to the OpenAI Compatible settings section, defaulting to `https://api.openai.com/v1`
- Add a "Reset to Default" button next to the Base URL field that restores the default OpenAI base URL
- Change the default model from `gpt-4o-mini` to `gpt-5`
- Replace the model Picker/Custom dropdown with a free-text **Model** field pre-filled with `gpt-5`, plus a "Reset to Default" button to restore it
- Persist base URL and model in UserDefaults via `PreferencesService`
- Update `OpenAITranslationService` to use the configured base URL instead of the hardcoded URL

## Capabilities

### New Capabilities
- `openai-compatible-config`: Configurable base URL and model for OpenAI-compatible API endpoints, with default values and reset-to-default functionality

### Modified Capabilities
- `settings-management`: Settings UI changes to rename "OpenAI" section to "OpenAI Compatible", replace model picker with free-text field, and add base URL configuration with reset buttons

## Impact

- **Views**: `SettingsView.swift` — restructure the OpenAI section with new fields and reset buttons
- **Models**: `Models.swift` — update `TranslationEngine.openAI` display name; may simplify/remove `openAIModels` list
- **Services**: `PreferencesService.swift` — add `openAIBaseURL` property with UserDefaults persistence
- **Services**: `OpenAITranslationService.swift` — accept and use configurable base URL
- **ViewModels**: `TranslationViewModel.swift` — pass base URL to `OpenAITranslationService`
