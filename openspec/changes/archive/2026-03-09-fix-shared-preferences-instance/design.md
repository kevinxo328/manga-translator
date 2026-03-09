## Context

`PreferencesService` is an `ObservableObject` that reads/writes user preferences via `UserDefaults`. Currently two independent instances exist at runtime: one owned by `TranslationViewModel` and one owned by `SettingsView`. This means settings changes made in the Settings window are never propagated to the ViewModel's in-memory state, causing stale translation preferences.

## Goals / Non-Goals

**Goals:**
- Ensure a single `PreferencesService` instance is shared across the whole app
- Settings changes in the Settings window are immediately reflected when the next translation runs
- No user-visible behavior change beyond the bug fix

**Non-Goals:**
- Auto-retranslating open pages when settings change (user can use existing "Re-translate" buttons)
- Changing how preferences are stored (UserDefaults keys remain the same)

## Decisions

### Lift PreferencesService to App level

Create `@StateObject private var preferences = PreferencesService()` in `MangaTranslatorApp` and inject it into both `TranslationViewModel` and `SettingsView`.

**Alternatives considered:**
- Pass `viewModel.preferences` to `SettingsView` — simpler change but couples SettingsView to the ViewModel, which is wrong conceptually. Settings should not depend on translation state.
- Re-read UserDefaults before each translation — a workaround that doesn't fix the architecture and could introduce timing issues.

### TranslationViewModel accepts PreferencesService via init

Change `TranslationViewModel.init()` to accept `preferences: PreferencesService`. Store it as `@Published var preferences: PreferencesService`.

The `@Published` wrapper is required to preserve SwiftUI's nested `ObservableObject` forwarding: when `preferences.sourceLanguage` changes, `preferences.objectWillChange` fires, which is automatically forwarded to `viewModel.objectWillChange` because the property is `@Published`. Without it, `ContentView` would not re-render on preference changes and `onChange` bindings in the toolbar would stop triggering.

### SettingsView switches from @StateObject to @ObservedObject

`@StateObject` means SwiftUI owns the lifecycle — changing to `@ObservedObject` means an external owner (the App) manages it.

## Risks / Trade-offs

- [Risk] `TranslationViewModel` init signature change may affect previews or tests → Mitigation: Update any call sites; PreferencesService has a simple no-arg init so tests can pass a fresh instance.
- [Risk] Removing `@Published` from `viewModel.preferences` could break bindings in `ContentView` that use `$viewModel.preferences.*` → Mitigation: Bindings like `$viewModel.preferences.sourceLanguage` bind to the PreferencesService's own `@Published` properties, so they remain reactive regardless.

## Migration Plan

1. Update `TranslationViewModel.init(preferences:)`
2. Update `MangaTranslatorApp` to own the `PreferencesService` and inject it
3. Update `SettingsView` to accept `@ObservedObject var preferences`
4. No data migration needed — UserDefaults keys are unchanged
