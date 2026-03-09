## Why

`SettingsView` and `TranslationViewModel` each create their own `PreferencesService` instance. When the user updates settings in the Settings window, changes are written to `UserDefaults` but the ViewModel's in-memory instance is never updated, so translations continue using stale preferences until the app restarts.

## What Changes

- `MangaTranslatorApp` creates a single `@StateObject var preferences: PreferencesService` and passes it to both `TranslationViewModel` and `SettingsView`
- `TranslationViewModel.init()` accepts a `PreferencesService` parameter instead of instantiating its own
- `SettingsView` receives `preferences` as `@ObservedObject` instead of owning a `@StateObject`

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `settings-management`: Settings changes must be immediately reflected in the active translation session without requiring an app restart.

## Impact

- `MangaTranslatorApp.swift`
- `TranslationViewModel.swift`
- `SettingsView.swift`
