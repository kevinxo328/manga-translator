## ADDED Requirements

### Requirement: Model picker UI in API Keys tab
Each LLM provider (Claude, OpenAI) displays a model picker below its API key input in the Settings API Keys tab.

#### Scenario: User views API Keys tab
- **WHEN** the user opens Settings and selects the API Keys tab
- **THEN** a model picker is displayed below the Claude API key input and below the OpenAI API key input
- **THEN** non-LLM providers (DeepL, Google) do not show a model picker

#### Scenario: User selects a different Claude model
- **WHEN** the user picks a model from the Claude model picker
- **THEN** the selection is persisted immediately
- **THEN** subsequent translations using the Claude engine use the newly selected model

#### Scenario: User selects a different OpenAI model
- **WHEN** the user picks a model from the OpenAI model picker
- **THEN** the selection is persisted immediately
- **THEN** subsequent translations using the OpenAI engine use the newly selected model

### Requirement: Model selection persistence
Selected models are stored in UserDefaults and restored on app launch.

#### Scenario: App restart preserves model choice
- **WHEN** the user selects a Claude model and restarts the app
- **THEN** the previously selected model is shown in the picker
- **THEN** translations use the previously selected model

#### Scenario: Default model on first launch
- **WHEN** no model preference has been saved (first launch)
- **THEN** Claude defaults to `claude-sonnet-4-5-20250929`
- **THEN** OpenAI defaults to `gpt-4o-mini`

### Requirement: Predefined model list
Each LLM provider has a curated list of available models.

#### Scenario: Claude model options
- **WHEN** the user opens the Claude model picker
- **THEN** the available options include at least: Claude Sonnet 4.5, Claude Haiku 3.5

#### Scenario: OpenAI model options
- **WHEN** the user opens the OpenAI model picker
- **THEN** the available options include at least: GPT-4o mini, GPT-4o
