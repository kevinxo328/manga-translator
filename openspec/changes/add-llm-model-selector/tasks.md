## 1. Data Model

- [ ] 1.1 Add `LLMModel` struct (or similar) with `displayName` and `apiIdentifier` properties, and static arrays of available models for Claude and OpenAI on `TranslationEngine` in `Models.swift`
- [ ] 1.2 Add `claudeModel` and `openAIModel` published properties to `PreferencesService` with UserDefaults persistence, defaulting to `claude-sonnet-4-5-20250929` and `gpt-4o-mini`

## 2. Service Layer

- [ ] 2.1 Update `ClaudeTranslationService` to accept a model parameter instead of hardcoding `claude-sonnet-4-5-20250929`
- [ ] 2.2 Update `OpenAITranslationService` to accept a model parameter instead of hardcoding `gpt-4o-mini`
- [ ] 2.3 Update `TranslationViewModel.translationService` computed property to pass the selected model from `preferences` when creating LLM services

## 3. Settings UI

- [ ] 3.1 Add a model `Picker` below the Claude API key `SecureField` in `SettingsView` API Keys tab
- [ ] 3.2 Add a model `Picker` below the OpenAI API key `SecureField` in `SettingsView` API Keys tab
- [ ] 3.3 Bind pickers to `PreferencesService` model properties so changes persist immediately
