## ADDED Requirements

### Requirement: Settings changes apply immediately to active translation session
The system SHALL use a single shared `PreferencesService` instance across the Settings window and the translation pipeline, so that any preference change (language pair, engine, model) is reflected in the next translation without requiring an app restart.

#### Scenario: Language change applies to next translation
- **WHEN** user changes the target language in Settings
- **THEN** the next translation run uses the updated target language

#### Scenario: Engine change applies to next translation
- **WHEN** user changes the translation engine in Settings
- **THEN** the next translation run uses the updated engine

#### Scenario: Model change applies to next translation
- **WHEN** user changes the Claude or OpenAI model in Settings
- **THEN** the next translation run uses the updated model identifier
