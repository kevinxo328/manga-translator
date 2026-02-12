## ADDED Requirements

### Requirement: Configurable base URL for OpenAI-compatible API
The system SHALL allow users to configure a base URL for the OpenAI-compatible translation service. The default base URL SHALL be `https://api.openai.com/v1`. The system SHALL persist the base URL in UserDefaults.

#### Scenario: Default base URL on first launch
- **WHEN** a new user opens the OpenAI Compatible settings section
- **THEN** the Base URL field SHALL display `https://api.openai.com/v1`

#### Scenario: Custom base URL
- **WHEN** user enters `https://my-local-llm.example.com/v1` as the base URL
- **THEN** the system SHALL use `https://my-local-llm.example.com/v1/chat/completions` for API requests

#### Scenario: Reset base URL to default
- **WHEN** user clicks the "Reset to Default" button next to the Base URL field
- **THEN** the Base URL field SHALL be restored to `https://api.openai.com/v1`

### Requirement: Configurable model name for OpenAI-compatible API
The system SHALL allow users to enter any model name as free text. The default model SHALL be `gpt-5`. The system SHALL persist the model name in UserDefaults.

#### Scenario: Default model on first launch
- **WHEN** a new user opens the OpenAI Compatible settings section
- **THEN** the Model field SHALL display `gpt-5`

#### Scenario: Custom model name
- **WHEN** user enters `llama-3-70b` as the model name
- **THEN** the system SHALL use `llama-3-70b` in the API request body

#### Scenario: Reset model to default
- **WHEN** user clicks the "Reset to Default" button next to the Model field
- **THEN** the Model field SHALL be restored to `gpt-5`

### Requirement: Input sanitization for base URL and model
The system SHALL sanitize user inputs to prevent common configuration errors.

#### Scenario: Trailing slash in base URL
- **WHEN** user enters `https://api.openai.com/v1/` (with trailing slash)
- **THEN** the system SHALL strip the trailing slash before constructing the API request URL

#### Scenario: Leading slash in model name
- **WHEN** user enters `/gpt-5` (with leading slash)
- **THEN** the system SHALL strip the leading slash before using the model name in the API request

### Requirement: OpenAI-compatible service uses configured base URL
The system SHALL construct the API endpoint by appending `/chat/completions` to the configured base URL. The service SHALL use this endpoint for all translation requests.

#### Scenario: API request with custom base URL
- **WHEN** the base URL is set to `https://custom-api.example.com/v1` and a translation is requested
- **THEN** the system SHALL send the request to `https://custom-api.example.com/v1/chat/completions`
