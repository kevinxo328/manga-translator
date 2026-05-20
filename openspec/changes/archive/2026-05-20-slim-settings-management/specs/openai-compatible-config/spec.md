## ADDED Requirements

### Requirement: OpenAI Compatible section in Settings UI
The API Keys tab in Settings SHALL display the OpenAI-compatible configuration as a section titled "OpenAI Compatible" with a brain icon. The section SHALL contain an API Key secure field, a Base URL text field with a "Reset" button, and a Model text field with a "Reset" button. The Base URL default, Model default, and Reset behaviour are owned by this capability's "Configurable base URL for OpenAI-compatible API" and "Configurable model name for OpenAI-compatible API" requirements.

#### Scenario: OpenAI Compatible section layout
- **WHEN** user views the API Keys tab
- **THEN** the section header SHALL display "OpenAI Compatible" with a brain icon
- **AND** the section SHALL contain an API Key secure field, a Base URL text field with a "Reset" button, and a Model text field with a "Reset" button

## MODIFIED Requirements

### Requirement: Configurable base URL for OpenAI-compatible API
The system SHALL allow users to configure a base URL for the OpenAI-compatible translation service. The default base URL SHALL be `https://api.openai.com/v1`. The system SHALL persist the base URL in UserDefaults across app launches.

#### Scenario: Default base URL on first launch
- **WHEN** a new user opens the OpenAI Compatible settings section
- **THEN** the Base URL field SHALL display `https://api.openai.com/v1`

#### Scenario: Custom base URL
- **WHEN** user enters `https://my-local-llm.example.com/v1` as the base URL
- **THEN** the system SHALL use `https://my-local-llm.example.com/v1/chat/completions` for API requests

#### Scenario: Reset base URL to default
- **WHEN** user clicks the "Reset" button next to the Base URL field
- **THEN** the Base URL field SHALL be restored to `https://api.openai.com/v1`

#### Scenario: OpenAI base URL persists across launches
- **WHEN** user sets the OpenAI base URL to `https://custom-api.example.com/v1` and quits the app
- **THEN** the app launches with the custom base URL pre-filled

### Requirement: Configurable model name for OpenAI-compatible API
The system SHALL allow users to enter any model name as free text. The default model SHALL be `gpt-5`. The system SHALL persist the model name in UserDefaults, and the next translation run after a model change SHALL use the updated model identifier without requiring an app restart.

#### Scenario: Default model on first launch
- **WHEN** a new user opens the OpenAI Compatible settings section
- **THEN** the Model field SHALL display `gpt-5`

#### Scenario: Custom model name
- **WHEN** user enters `llama-3-70b` as the model name
- **THEN** the system SHALL use `llama-3-70b` in the API request body

#### Scenario: Reset model to default
- **WHEN** user clicks the "Reset" button next to the Model field
- **THEN** the Model field SHALL be restored to `gpt-5`

#### Scenario: Model change applies to next translation
- **WHEN** user changes the OpenAI model in Settings
- **THEN** the next translation run uses the updated model identifier
