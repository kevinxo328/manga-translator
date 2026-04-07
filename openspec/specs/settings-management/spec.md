## Purpose

User preferences persistence and settings UI.

## Requirements

### Requirement: Store user preferences in UserDefaults
The system SHALL persist user preferences (default source language, default target language, default translation engine, concurrent translation limit, OpenAI base URL, OpenAI model name, GitHub Copilot model name) using UserDefaults.

#### Scenario: Preferences persist across launches
- **WHEN** user sets default language pair to Japanese → Traditional Chinese and quits the app
- **THEN** the app launches with Japanese → Traditional Chinese pre-selected

#### Scenario: OpenAI base URL persists across launches
- **WHEN** user sets the OpenAI base URL to `https://custom-api.example.com/v1` and quits the app
- **THEN** the app launches with the custom base URL pre-filled

### Requirement: Store API keys in Keychain
The system SHALL store translation service API keys (DeepL, Google, OpenAI) in the macOS Keychain using the Security framework. Keys SHALL be stored per-service with the app's bundle ID as the service identifier.

#### Scenario: Save API key
- **WHEN** user enters their DeepL API key in settings
- **THEN** the key is stored in Keychain and persists across app launches

#### Scenario: Retrieve API key
- **WHEN** user initiates a DeepL translation
- **THEN** the system retrieves the DeepL API key from Keychain

### Requirement: Settings UI
The system SHALL provide a settings view (accessible via Cmd+,) where users can configure API keys, default language pair, default translation engine, and update preferences. The Preferences tab SHALL include an "Updates" section with a toggle for automatic update checking and a "Check for Updates Now" button. The OpenAI section SHALL be renamed to "OpenAI Compatible" and SHALL include a Base URL text field, a free-text Model field, and "Reset" buttons for both fields. The `UpdateSettingsView` component SHALL own its `CheckForUpdatesViewModel` using `@StateObject` to ensure the ViewModel is retained across parent re-renders. All language selection pickers SHALL display languages using international standard short codes (e.g., JA, EN, ZH-TW) for consistency and space efficiency. The API Keys tab SHALL include a GitHub Copilot section that displays the availability status of the Copilot CLI and, when available, a model picker populated from the Copilot API. The engine picker in the Preferences tab SHALL only show the GitHub Copilot option when the Copilot CLI is installed and logged in.

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

#### Scenario: Language picker display codes
- **WHEN** user opens the language selection picker in settings or the toolbar
- **THEN** the options SHALL be displayed as JA, EN, and ZH-TW

#### Scenario: GitHub Copilot section — CLI detected
- **WHEN** user opens the API Keys tab and the Copilot CLI is installed and logged in
- **THEN** a green checkmark label "Copilot CLI detected" is shown with a model picker populated from the Copilot API

#### Scenario: GitHub Copilot section — CLI not installed
- **WHEN** user opens the API Keys tab and the Copilot CLI binary is not found
- **THEN** a label "GitHub Copilot CLI not found" is shown with installation instructions

#### Scenario: GitHub Copilot section — not logged in
- **WHEN** user opens the API Keys tab and the CLI is installed but no keychain token exists
- **THEN** a warning "Not logged in" is shown with instructions to run `copilot login`

#### Scenario: Engine picker hides Copilot when unavailable
- **WHEN** user opens the engine picker in the Preferences tab and Copilot CLI is not installed or not logged in
- **THEN** the "GitHub Copilot" option is not shown in the picker

### Requirement: Validate API key presence before translation
The system SHALL check that the required API key exists before attempting translation. If the key is missing, the system SHALL prompt the user to enter it in settings.

#### Scenario: Missing API key
- **WHEN** user selects DeepL engine but has not entered an API key
- **THEN** the system shows an alert directing the user to settings to enter the key

### Requirement: Settings changes apply immediately to active translation session
The system SHALL use a single shared `PreferencesService` instance across the Settings window and the translation pipeline, so that any preference change (language pair, engine, model) is reflected in the next translation without requiring an app restart.

#### Scenario: Language change applies to next translation
- **WHEN** user changes the target language in Settings
- **THEN** the next translation run uses the updated target language

#### Scenario: Engine change applies to next translation
- **WHEN** user changes the translation engine in Settings
- **THEN** the next translation run uses the updated engine

#### Scenario: Model change applies to next translation
- **WHEN** user changes the OpenAI model in Settings
- **THEN** the next translation run uses the updated model identifier
