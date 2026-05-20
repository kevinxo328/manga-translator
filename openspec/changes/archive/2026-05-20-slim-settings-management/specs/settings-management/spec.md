## MODIFIED Requirements

### Requirement: Store user preferences in UserDefaults
The system SHALL persist cross-capability user preferences (default source language, default target language, default translation engine, concurrent translation limit) using UserDefaults. Capability-specific preference keys are persisted by their owner capability specs and not enumerated here.

#### Scenario: Preferences persist across launches
- **WHEN** user sets default language pair to Japanese → Traditional Chinese and quits the app
- **THEN** the app launches with Japanese → Traditional Chinese pre-selected

### Requirement: Settings UI
The system SHALL provide a settings view accessible via Cmd+,. The settings window SHALL use a tabbed structure. Each tab's content is owned by the corresponding capability (`auto-update` for the Updates section, `copilot-model-management` for the GitHub Copilot section, `openai-compatible-config` for the OpenAI Compatible section, `local-model-lifecycle` for the High-Accuracy OCR section, `debug-log-management` for the Debug tab). All language selection pickers SHALL display languages using flag emoji and full English names (e.g., `"🇯🇵 Japanese"`, `"🇺🇸 English"`, `"🇹🇼 Traditional Chinese"`).

#### Scenario: Open settings
- **WHEN** user presses Cmd+,
- **THEN** the settings window opens

#### Scenario: Language picker display codes
- **WHEN** user opens the source language picker in settings or the toolbar
- **THEN** the options SHALL be displayed as `"🇯🇵 Japanese"` and `"🇺🇸 English"` only
- **WHEN** user opens the target language picker in settings or the toolbar
- **THEN** the options SHALL be displayed as `"🇯🇵 Japanese"`, `"🇺🇸 English"`, and `"🇹🇼 Traditional Chinese"`

### Requirement: Settings changes apply immediately to active translation session
The system SHALL use a single shared `PreferencesService` instance across the Settings window and the translation pipeline, so that any preference change (language pair, engine) is reflected in the next translation without requiring an app restart. Capability-specific live-apply scenarios (e.g., OpenAI model change) are owned by the corresponding capability spec.

#### Scenario: Language change applies to next translation
- **WHEN** user changes the target language in Settings
- **THEN** the next translation run uses the updated target language

#### Scenario: Engine change applies to next translation
- **WHEN** user changes the translation engine in Settings
- **THEN** the next translation run uses the updated engine

## REMOVED Requirements

### Requirement: High-accuracy OCR settings section
**Reason**: The Settings UI for high-accuracy OCR surfaces `local-model-lifecycle` states (device capability, download state, enabled flag). The capability that owns those states should own how users observe and interact with them from Settings.
**Migration**: Use `local-model-lifecycle` requirement `High-accuracy OCR settings section`.

#### Scenario: High-accuracy OCR settings scenarios moved to lifecycle owner
- **WHEN** a high-accuracy OCR Settings UI scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Confirm before deleting model data
**Reason**: The deletion confirmation gates `ModelDownloadService.delete()`, which is owned by `local-model-lifecycle`. The confirmation dialog is part of the user-initiated delete flow.
**Migration**: Use `local-model-lifecycle` requirement `Confirm before deleting model data`.

#### Scenario: Delete confirmation scenarios moved to lifecycle owner
- **WHEN** a model-delete confirmation scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`

### Requirement: Persist high-accuracy OCR preference
**Reason**: The high-accuracy OCR enabled flag is a state-machine variable owned by `local-model-lifecycle`. Its UserDefaults persistence and the rejection scenarios that surface state-machine decisions belong with the owner.
**Migration**: Use `local-model-lifecycle` requirement `Persist high-accuracy OCR preference`.

#### Scenario: High-accuracy preference persistence scenarios moved to lifecycle owner
- **WHEN** a high-accuracy OCR enabled-flag persistence or enable-rejection scenario is needed
- **THEN** the scenario is specified by `local-model-lifecycle`
