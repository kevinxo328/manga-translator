## Purpose

Generic settings infrastructure: UserDefaults storage policy, Keychain serviceName policy, settings window opened via Cmd+,, shared PreferencesService instance, API-key-required gate, and language picker display format used by all translation engines.

## Requirements

### Requirement: Store user preferences in UserDefaults
The system SHALL persist cross-capability user preferences (default source language, default target language, default translation engine) using UserDefaults. Capability-specific preference keys are persisted by their owner capability specs and not enumerated here.

#### Scenario: Preferences persist across launches
- **WHEN** user sets default language pair to Japanese → Traditional Chinese and quits the app
- **THEN** the app launches with Japanese → Traditional Chinese pre-selected

### Requirement: Store API keys in Keychain
The system SHALL store translation service API keys (DeepL, Google, OpenAI) in the macOS Keychain using the Security framework. Keys SHALL be stored per-service using a stable, fixed service name constant ("com.chunweiliu.MangaTranslator") that does not change across build variants, TestFlight builds, or re-signing, ensuring credential continuity across app updates.

#### Scenario: Save API key
- **WHEN** user enters their DeepL API key in settings
- **THEN** the key is stored in Keychain and persists across app launches

#### Scenario: Retrieve API key
- **WHEN** user initiates a DeepL translation
- **THEN** the system retrieves the DeepL API key from Keychain

### Requirement: Settings UI
The system SHALL provide a settings view accessible via Cmd+,. The settings window SHALL use a tabbed sidebar structure with tabs in the following fixed order: **API Keys → Preferences → Glossary → Debug → About**. Each tab's content is owned by the corresponding capability (`auto-update` for the Updates section within Preferences, `copilot-model-management` for the GitHub Copilot section, `openai-compatible-config` for the OpenAI Compatible section, `local-model-lifecycle` for the High-Accuracy OCR section, `debug-log-management` for the Debug tab, `glossary-management` for the Glossary tab). All language selection pickers SHALL display languages using flag emoji and full English names (e.g., `"🇺🇸 English"`, `"🇯🇵 Japanese"`, `"🇹🇼 Traditional Chinese"`).

#### Scenario: Open settings
- **WHEN** user presses Cmd+,
- **THEN** the settings window opens and displays the API Keys tab on a fresh app launch, unless an in-memory deep-link has already selected another tab

#### Scenario: Language picker display labels
- **WHEN** user opens the source language picker in settings or the toolbar
- **THEN** the options SHALL be displayed as `"🇺🇸 English"` and `"🇯🇵 Japanese"` in that order
- **WHEN** user opens the target language picker in settings or the toolbar
- **THEN** the options SHALL be displayed as `"🇺🇸 English"`, `"🇫🇷 French"`, `"🇩🇪 German"`, `"🇮🇩 Indonesian"`, `"🇯🇵 Japanese"`, `"🇰🇷 Korean"`, `"🇧🇷 Portuguese (Brazil)"`, `"🇨🇳 Simplified Chinese"`, `"🇪🇸 Spanish"`, `"🇹🇼 Traditional Chinese"`, and `"🇻🇳 Vietnamese"` in that order

### Requirement: Programmatic tab deep-linking
The system SHALL support navigating to a specific Settings tab from outside the Settings window without persisting the destination to UserDefaults. `PreferencesService` SHALL expose an in-memory `@Published var activeTabIdentifier: String` that defaults to `"apiKeys"` on every fresh app launch and is never written to UserDefaults. The Settings window SHALL bind its visible tab to this identifier. The supported identifier values are `"apiKeys"`, `"preferences"`, `"glossary"`, `"debug"`, and `"about"`. An unsupported identifier value SHALL cause the Settings window to display the API Keys tab and normalize `activeTabIdentifier` back to `"apiKeys"`. Manual tab selection inside the Settings window SHALL update `activeTabIdentifier` to the canonical identifier of the selected tab.

#### Scenario: Main window deep-links to Glossary settings tab
- **WHEN** the user selects "Manage Glossaries..." from the main window toolbar glossary menu
- **THEN** the system sets `PreferencesService.activeTabIdentifier` to `"glossary"` and opens (or focuses) the Settings window
- **AND** the Settings window displays the Glossary tab

#### Scenario: Manual settings tab selection updates routing state
- **WHEN** the user manually selects a settings tab
- **THEN** `PreferencesService.activeTabIdentifier` is updated to that tab's canonical identifier
- **AND** the identifier is not written to UserDefaults

#### Scenario: Unknown active tab identifier falls back to API Keys
- **WHEN** `PreferencesService.activeTabIdentifier` is set to an unsupported string
- **THEN** the Settings window displays the API Keys tab
- **AND** `PreferencesService.activeTabIdentifier` is normalized back to `"apiKeys"`

#### Scenario: activeTabIdentifier resets on app launch
- **WHEN** the app launches fresh (no in-memory state carried over)
- **THEN** `PreferencesService.activeTabIdentifier` is `"apiKeys"`
- **AND** the Settings window opens to the API Keys tab

### Requirement: Validate API key presence before translation
The system SHALL check that the required API key exists before attempting translation. If the key is missing, the system SHALL prompt the user to enter it in settings.

#### Scenario: Missing API key
- **WHEN** user selects DeepL engine but has not entered an API key
- **THEN** the system shows an alert directing the user to settings to enter the key

### Requirement: Settings changes apply immediately to active translation session
The system SHALL use a single shared `PreferencesService` instance across the Settings window and the translation pipeline, so that any preference change (language pair, engine) is reflected in the next translation without requiring an app restart. Capability-specific live-apply scenarios (e.g., OpenAI model change) are owned by the corresponding capability spec.

#### Scenario: Language change applies to next translation
- **WHEN** user changes the target language in Settings
- **THEN** the next translation run uses the updated target language

#### Scenario: Engine change applies to next translation
- **WHEN** user changes the translation engine in Settings
- **THEN** the next translation run uses the updated engine
