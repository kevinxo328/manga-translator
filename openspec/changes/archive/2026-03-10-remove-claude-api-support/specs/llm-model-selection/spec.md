## MODIFIED Requirements

### Requirement: Model picker UI in API Keys tab
Each LLM provider (OpenAI Compatible) displays a model picker below its API key input in the Settings API Keys tab. Claude models are no longer supported.

#### Scenario: User views API Keys tab
- **WHEN** the user opens Settings and selects the API Keys tab
- **THEN** a model picker is displayed below the OpenAI API key input
- **THEN** Claude model picker is not displayed
- **THEN** non-LLM providers (DeepL, Google) do not show a model picker

### Requirement: Model selection persistence
Selected models are stored in UserDefaults and restored on app launch. Claude model persistence is removed.

#### Scenario: App restart preserves model choice
- **WHEN** the user selects an OpenAI model and restarts the app
- **THEN** the previously selected model is shown in the picker
- **THEN** translations use the previously selected model

#### Scenario: Default model on first launch
- **WHEN** no model preference has been saved (first launch)
- **THEN** OpenAI defaults to `gpt-4o-mini`

### Requirement: Predefined model list
Each LLM provider has a curated list of available models. Claude models are removed from the list.

#### Scenario: OpenAI model options
- **WHEN** the user opens the OpenAI model picker
- **THEN** the available options include at least: GPT-5, GPT-5 Turbo

## REMOVED Requirements

### Requirement: Claude model options
**Reason**: Claude service is removed.
**Migration**: Use OpenAI Compatible models.

#### Scenario: Claude model options
- **WHEN** the user opens the Claude model picker
- **THEN** the available options include at least: Claude Sonnet 4.5, Claude Haiku 3.5
