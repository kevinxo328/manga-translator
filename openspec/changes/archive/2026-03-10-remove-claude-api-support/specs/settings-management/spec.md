## MODIFIED Requirements

### Requirement: Store user preferences in UserDefaults
The system SHALL persist user preferences (default source language, default target language, default translation engine, concurrent translation limit, OpenAI base URL, OpenAI model name) using UserDefaults. Claude-specific preferences are removed.

#### Scenario: Preferences persist across launches
- **WHEN** user sets default language pair to Japanese → Traditional Chinese and quits the app
- **THEN** the app launches with Japanese → Traditional Chinese pre-selected

#### Scenario: OpenAI base URL persists across launches
- **WHEN** user sets the OpenAI base URL to `https://custom-api.example.com/v1` and quits the app
- **THEN** the app launches with the custom base URL pre-filled

### Requirement: Store API keys in Keychain
The system SHALL store translation service API keys (DeepL, Google, OpenAI) in the macOS Keychain using the Security framework. Claude/Anthropic keys are no longer stored or retrieved.

#### Scenario: Save API key
- **WHEN** user enters their DeepL API key in settings
- **THEN** the key is stored in Keychain and persists across app launches

#### Scenario: Retrieve API key
- **WHEN** user initiates a DeepL translation
- **THEN** the system retrieves the DeepL API key from Keychain

### Requirement: Validate API key presence before translation
The system SHALL check that the required API key exists before attempting translation. If the key is missing, the system SHALL prompt the user to enter it in settings. Reference to Claude is removed.

#### Scenario: Missing API key
- **WHEN** user selects DeepL engine but has not entered an API key
- **THEN** the system shows an alert directing the user to settings to enter the key

### Requirement: Settings changes apply immediately to active translation session
The system SHALL use a single shared `PreferencesService` instance across the Settings window and the translation pipeline, so that any preference change (language pair, engine, model) is reflected in the next translation without requiring an app restart. Claude model changes are removed.

#### Scenario: Engine change applies to next translation
- **WHEN** user changes the translation engine in Settings
- **THEN** the next translation run uses the updated engine

#### Scenario: Model change applies to next translation
- **WHEN** user changes the OpenAI model in Settings
- **THEN** the next translation run uses the updated model identifier

## REMOVED Requirements

### Requirement: Validate Claude API key
**Reason**: Claude service is removed.
**Migration**: N/A

#### Scenario: Missing API key
- **WHEN** user selects Claude engine but has not entered an Anthropic API key
- **THEN** the system shows an alert directing the user to settings to enter the key
