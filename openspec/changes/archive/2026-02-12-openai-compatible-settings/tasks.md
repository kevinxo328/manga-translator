## 1. Models and Constants

- [x] 1.1 Update `TranslationEngine.openAI.displayName` from "OpenAI" to "OpenAI Compatible" in `Models.swift`
- [x] 1.2 Add default constants: `defaultOpenAIBaseURL = "https://api.openai.com/v1"` and `defaultOpenAIModel = "gpt-5"` (e.g., as static properties on `PreferencesService`)

## 2. Preferences Persistence

- [x] 2.1 Add `openAIBaseURL` published property to `PreferencesService` with UserDefaults persistence, defaulting to `https://api.openai.com/v1`
- [x] 2.2 Update default value for `openAIModel` from `gpt-4o-mini` to `gpt-5`

## 3. Settings UI

- [x] 3.1 Rename the OpenAI section header in `SettingsView.swift` from "OpenAI" to "OpenAI Compatible"
- [x] 3.2 Replace the model `Picker` + custom field with a single `TextField` bound to `preferences.openAIModel`, plus a "Reset to Default" button
- [x] 3.3 Add a Base URL `TextField` bound to `preferences.openAIBaseURL`, plus a "Reset to Default" button
- [x] 3.4 Remove `selectedOpenAIModel`, `customOpenAIModel` state variables and related `loadKeys()` logic that is no longer needed

## 4. Service Layer

- [x] 4.1 Update `OpenAITranslationService.init` to accept a `baseURL` parameter
- [x] 4.2 Update `callAPI` to construct the endpoint URL from the `baseURL` parameter instead of the hardcoded URL, appending `/chat/completions`
- [x] 4.3 Add input sanitization: strip trailing `/` from base URL and leading `/` from model name before constructing the request

## 5. ViewModel Wiring

- [x] 5.1 Update `TranslationViewModel` to pass `preferences.openAIBaseURL` when creating `OpenAITranslationService`

## 6. Cleanup

- [x] 6.1 Remove or deprecate `TranslationEngine.openAIModels` static list from `Models.swift` if no longer used
