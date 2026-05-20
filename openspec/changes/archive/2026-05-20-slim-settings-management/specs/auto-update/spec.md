## ADDED Requirements

### Requirement: Updates section in Settings UI
The Preferences tab in Settings SHALL include an "Updates" section with a toggle for automatic update checking and a "Check for Updates Now" button. The `UpdateSettingsView` component SHALL own its `CheckForUpdatesViewModel` using `@StateObject` to ensure the ViewModel is retained across parent re-renders.

#### Scenario: Toggle automatic updates
- **WHEN** user toggles the automatic update check setting
- **THEN** the preference is persisted and Sparkle respects the new setting on next launch

#### Scenario: Manual update check from settings
- **WHEN** user clicks "Check for Updates Now" in the Preferences tab
- **THEN** Sparkle performs an update check and displays the result

#### Scenario: UpdateSettingsView ViewModel survives parent re-render
- **WHEN** `SettingsView` body is re-evaluated (e.g., due to preference change)
- **THEN** `UpdateSettingsView` retains the same `CheckForUpdatesViewModel` instance
