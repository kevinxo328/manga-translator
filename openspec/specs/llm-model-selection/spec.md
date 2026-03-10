# llm-model-selection

## Purpose
Enable users to select specific LLM models for translation providers (OpenAI Compatible) and support manual model identifier input for power users.

## Requirements

### Requirement: Model picker UI in API Keys tab
Each LLM provider (OpenAI Compatible) displays a model picker below its API key input in the Settings API Keys tab.

#### Scenario: User views API Keys tab
- **WHEN** the user opens Settings and selects the API Keys tab
- **THEN** a model picker is displayed below the OpenAI API key input
- **THEN** non-LLM providers (DeepL, Google) do not show a model picker

#### Scenario: User selects a different OpenAI model
- **WHEN** the user picks a model from the OpenAI model picker
- **THEN** the selection is persisted immediately
- **THEN** subsequent translations using the OpenAI engine use the newly selected model

### Requirement: Model selection persistence
Selected models are stored in UserDefaults and restored on app launch.

#### Scenario: App restart preserves model choice
- **WHEN** the user selects an OpenAI model and restarts the app
- **THEN** the previously selected model is shown in the picker
- **THEN** translations use the previously selected model

#### Scenario: Default model on first launch
- **WHEN** no model preference has been saved (first launch)
- **THEN** OpenAI defaults to `gpt-4o-mini`

### Requirement: Predefined model list
Each LLM provider (OpenAI Compatible) has a curated list of available models.

#### Scenario: OpenAI model options
- **WHEN** the user opens the OpenAI model picker
- **THEN** the available options include at least: GPT-5, GPT-5 Turbo

### Requirement: Manual model identifier input
Users can enter a custom model identifier if it's not in the predefined list.

#### Scenario: User enters custom model
- **WHEN** the user selects "Custom..." from the model picker
- **THEN** a text field appears for manual entry
- **THEN** the entered value is used for API calls and persisted
