## Purpose

User preferences persistence and settings UI.

## Requirements

### Requirement: Store user preferences in UserDefaults
The system SHALL persist user preferences (default source language, default target language, default translation engine, concurrent translation limit) using UserDefaults.

#### Scenario: Preferences persist across launches
- **WHEN** user sets default language pair to Japanese → Traditional Chinese and quits the app
- **THEN** the app launches with Japanese → Traditional Chinese pre-selected

### Requirement: Store API keys in Keychain
The system SHALL store translation service API keys (DeepL, Google, OpenAI, Anthropic) in the macOS Keychain using the Security framework. Keys SHALL be stored per-service with the app's bundle ID as the service identifier.

#### Scenario: Save API key
- **WHEN** user enters their DeepL API key in settings
- **THEN** the key is stored in Keychain and persists across app launches

#### Scenario: Retrieve API key
- **WHEN** user initiates a DeepL translation
- **THEN** the system retrieves the DeepL API key from Keychain

### Requirement: Settings UI
The system SHALL provide a settings view (accessible via Cmd+,) where users can configure API keys, default language pair, and default translation engine.

#### Scenario: Open settings
- **WHEN** user presses Cmd+,
- **THEN** the settings window opens showing API key fields and default preferences

### Requirement: Validate API key presence before translation
The system SHALL check that the required API key exists before attempting translation. If the key is missing, the system SHALL prompt the user to enter it in settings.

#### Scenario: Missing API key
- **WHEN** user selects Claude engine but has not entered an Anthropic API key
- **THEN** the system shows an alert directing the user to settings to enter the key
