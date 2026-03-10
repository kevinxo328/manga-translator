## Context

The current system supports Claude as a translation engine. This requires specialized service logic, UI settings, and preference storage. Removing Claude simplifies the codebase and maintenance.

## Goals / Non-Goals

**Goals:**
- Completely remove `ClaudeTranslationService.swift`.
- Remove `claude` case from `TranslationEngine` and associated UI components.
- Cleanup preferences and keychain data related to Claude.
- Ensure the app remains stable and correctly defaults to another engine if Claude was previously selected.

**Non-Goals:**
- Removing any other translation services (DeepL, Google, OpenAI).
- Refactoring the entire `TranslationService` protocol or architecture beyond simple removals.

## Decisions

- **TranslationEngine Enum**: Remove `.claude` case. The `displayName` and `isLLM` switch statements will also be updated.
- **Service Deletion**: Delete `MangaTranslator/Services/ClaudeTranslationService.swift` and remove it from the Xcode project file.
- **Settings UI**: Remove the "Anthropic (Claude)" section from `SettingsView.swift`, including all associated `@State` variables and initializers.
- **Preferences Handling**: 
  - Update `PreferencesService.swift` to remove `claudeModel` and `claudeModel` storage.
  - If the previously selected engine was `.claude`, fallback to `.openAI` or `.deepL`.
- **ViewModel Update**: Remove `.claude` case from `TranslationViewModel.swift`'s translation provider factory method.

## Risks / Trade-offs

- **[Risk] Migration of Existing Users** → Users who have `.claude` selected in their preferences will encounter an invalid engine state. 
  - **Mitigation**: Update `PreferencesService` to fallback to a valid engine (e.g., `.openAI`) if the stored engine is no longer valid.
- **[Risk] Keychain Secrets** → The Claude API key might persist in the user's keychain. 
  - **Mitigation**: While we could attempt to delete it, keeping it doesn't harm the app's functionality; however, it's cleaner to remove the key retrieval logic.
