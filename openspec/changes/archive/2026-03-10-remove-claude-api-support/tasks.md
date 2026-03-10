## 1. Models and Preferences Cleanup

- [x] 1.1 Remove `.claude` case from `TranslationEngine` enum in `Models.swift`
- [x] 1.2 Update `TranslationEngine`'s `displayName` and `isLLM` switch statements in `Models.swift`
- [x] 1.3 Remove `claudeModels` static property from `TranslationEngine` extension in `Models.swift`
- [x] 1.4 Remove `claudeModel` property and its persistence logic from `PreferencesService.swift`
- [x] 1.5 Update `PreferencesService.init` to fallback to `.openAI` if the stored `translationEngine` is no longer valid (was `.claude`)

## 2. Service and ViewModel Updates

- [x] 2.1 Remove `.claude` case from `TranslationViewModel.swift`'s translation service factory logic
- [x] 2.2 Ensure no other services or view models reference `ClaudeTranslationService`

## 3. UI Cleanup (SettingsView)

- [x] 3.1 Remove `claudeKey`, `selectedClaudeModel`, and `customClaudeModel` state variables from `SettingsView.swift`
- [x] 3.2 Remove the "Anthropic (Claude)" section from the API Keys tab in `SettingsView.swift`
- [x] 3.3 Remove Claude-related initialization and persistence logic in `SettingsView.swift`'s `.onAppear` and `.onChange` modifiers

## 4. Final Deletion and Project Cleanup

- [x] 4.1 Delete `MangaTranslator/Services/ClaudeTranslationService.swift` from the file system
- [x] 4.2 Remove `ClaudeTranslationService.swift` references from `MangaTranslator.xcodeproj/project.pbxproj`
- [x] 4.3 Verify the app builds successfully and all other translation engines function as expected
