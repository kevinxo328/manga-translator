## 1. Data Model

- [x] 1.1 Add `LLMModel` struct (or similar) with `displayName` and `apiIdentifier` properties, and static arrays of available models for Claude and OpenAI on `TranslationEngine` in `Models.swift`
- [x] 1.2 Update `openAIModels` to use GPT-5 series (`gpt-5`, `gpt-5-turbo`)
- [x] 1.3 Add `claudeModel` and `openAIModel` published properties to `PreferencesService` with UserDefaults persistence

## 2. Service Layer

- [x] 2.1 Update `ClaudeTranslationService` to accept a model parameter
- [x] 2.2 Update `OpenAITranslationService` to accept a model parameter
- [x] 2.3 Update `TranslationViewModel.translationService` computed property

## 3. Settings UI

- [x] 3.1 Add a model `Picker` for Claude and OpenAI
- [x] 3.2 Add "Custom..." option to pickers and a `TextField` for manual model identifier entry when "Custom" is selected
- [x] 3.3 Bind pickers to `PreferencesService` model properties
