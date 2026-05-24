## MODIFIED Requirements

### Requirement: Settings UI
The system SHALL provide a settings view accessible via Cmd+,. The settings window SHALL use a tabbed structure. Each tab's content is owned by the corresponding capability (`auto-update` for the Updates section, `copilot-model-management` for the GitHub Copilot section, `openai-compatible-config` for the OpenAI Compatible section, `local-model-lifecycle` for the High-Accuracy OCR section, `debug-log-management` for the Debug tab, `glossary-rename-settings-ui` for the Glossary tab). All language selection pickers SHALL display languages using flag emoji and full English names (e.g., `"🇯🇵 Japanese"`, `"🇺🇸 English"`, `"🇹🇼 Traditional Chinese"`). The settings window SHALL support programmatic active tab deep-linking from the main window through a non-persistent `PreferencesService.activeTabIdentifier` string. Supported tab identifiers SHALL be `"apiKeys"`, `"preferences"`, `"debug"`, `"about"`, and `"glossary"`; unknown identifiers SHALL fall back to `"apiKeys"`.

#### Scenario: Open settings
- **WHEN** user presses Cmd+,
- **THEN** the settings window opens
- **AND** the settings window displays the API Keys tab on a fresh app launch unless an in-memory deep-link has selected another tab

#### Scenario: Language picker display codes
- **WHEN** user opens the source language picker in settings or the toolbar
- **THEN** the options SHALL be displayed as `"🇯🇵 Japanese"` and `"🇺🇸 English"` only
- **WHEN** user opens the target language picker in settings or the toolbar
- **THEN** the options SHALL be displayed as `"🇯🇵 Japanese"`, `"🇺🇸 English"`, and `"🇹🇼 Traditional Chinese"`

#### Scenario: Main window deep-links to Glossary settings tab
- **WHEN** the user selects `Manage Glossaries...` from the main window Glossary toolbar menu
- **THEN** the system sets `PreferencesService.activeTabIdentifier` to `"glossary"` and opens the Settings window
- **AND** the settings window displays focused on the Glossary tab

#### Scenario: Manual settings tab selection updates routing state
- **WHEN** the user manually selects a settings tab
- **THEN** `PreferencesService.activeTabIdentifier` is updated to that tab's supported identifier
- **AND** the selected tab identifier is not written to `UserDefaults`

#### Scenario: Invalid active tab identifier falls back
- **WHEN** `PreferencesService.activeTabIdentifier` is set to an unsupported string
- **THEN** the settings window displays the API Keys tab
- **AND** `PreferencesService.activeTabIdentifier` is normalized back to `"apiKeys"`
