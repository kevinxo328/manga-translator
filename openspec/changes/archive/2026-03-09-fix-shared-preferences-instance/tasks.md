## 1. Update TranslationViewModel

- [x] 1.1 Add a failing test in `MangaTranslatorTests/PreferencesServiceTests.swift`: create two `PreferencesService` instances, verify that changing one does NOT affect the other (documents the current broken state)
- [x] 1.2 Change `TranslationViewModel.init()` to accept `preferences: PreferencesService` and assign it to `self.preferences`
- [x] 1.3 Remove the inline `@Published var preferences = PreferencesService()` initializer

## 2. Update MangaTranslatorApp

- [x] 2.1 In `MangaTranslatorApp.swift`, add `@StateObject private var preferences = PreferencesService()` and update `init()` to initialize both `_preferences` and `_viewModel` using the same `PreferencesService` instance via `StateObject(wrappedValue:)`
- [x] 2.2 Pass `preferences` to `TranslationViewModel(preferences:)`
- [x] 2.3 Pass `preferences` to `SettingsView(preferences:onClearCache:updater:)`

## 3. Update SettingsView

- [x] 3.1 Replace `@StateObject private var preferences = PreferencesService()` with `@ObservedObject var preferences: PreferencesService`
- [x] 3.2 Update `SettingsView.init()` to accept `preferences: PreferencesService` as a parameter

## 4. Verify

- [x] 4.1 Add a passing test in `MangaTranslatorTests/PreferencesServiceTests.swift`: create a single `PreferencesService`, pass it to `TranslationViewModel(preferences:)`, change `preferences.targetLanguage`, and assert `viewModel.preferences.targetLanguage` reflects the change
- [x] 4.2 Build the app and confirm no compilation errors
- [x] 4.3 Manually verify: open Settings, change engine, close Settings, run a translation — confirm the new engine is used
