## MODIFIED Requirements

### Requirement: Settings UI
The system SHALL provide a settings view (accessible via Cmd+,) where users can configure API keys, default language pair, default translation engine, and update preferences. The Preferences tab SHALL include an "Updates" section with a toggle for automatic update checking and a "Check for Updates Now" button. The OpenAI section SHALL be renamed to "OpenAI Compatible" and SHALL include a Base URL text field, a free-text Model field, and "Reset" buttons for both fields. The `UpdateSettingsView` component SHALL own its `CheckForUpdatesViewModel` using `@StateObject` to ensure the ViewModel is retained across parent re-renders.

#### Scenario: Open settings
- **WHEN** user presses Cmd+,
- **THEN** the settings window opens showing API key fields, default preferences, and update preferences

#### Scenario: Toggle automatic updates
- **WHEN** user toggles the automatic update check setting
- **THEN** the preference is persisted and Sparkle respects the new setting on next launch

#### Scenario: Manual update check from settings
- **WHEN** user clicks "Check for Updates Now" in the Preferences tab
- **THEN** Sparkle performs an update check and displays the result

#### Scenario: OpenAI Compatible section layout
- **WHEN** user views the API Keys tab
- **THEN** the section header SHALL display "OpenAI Compatible" with a brain icon
- **AND** the section SHALL contain an API Key secure field, a Base URL text field with a "Reset" button, and a Model text field with a "Reset" button

#### Scenario: UpdateSettingsView ViewModel survives parent re-render
- **WHEN** `SettingsView` body is re-evaluated (e.g., due to preference change)
- **THEN** `UpdateSettingsView` retains the same `CheckForUpdatesViewModel` instance
