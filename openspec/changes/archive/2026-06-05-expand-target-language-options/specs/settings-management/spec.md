## MODIFIED Requirements

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
