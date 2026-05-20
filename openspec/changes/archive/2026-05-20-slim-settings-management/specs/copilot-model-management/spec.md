## ADDED Requirements

### Requirement: GitHub Copilot section in Settings UI
The API Keys tab in Settings SHALL include a GitHub Copilot section that displays the availability status of the Copilot CLI and, when available, a model picker populated from the Copilot API. The engine picker in the Preferences tab SHALL only show the GitHub Copilot option when the Copilot CLI is installed and logged in.

#### Scenario: GitHub Copilot section — CLI detected
- **WHEN** user opens the API Keys tab and the Copilot CLI is installed and logged in
- **THEN** a green checkmark label "Copilot CLI detected" is shown with a model picker populated from the Copilot API

#### Scenario: GitHub Copilot section — CLI not installed
- **WHEN** user opens the API Keys tab and the Copilot CLI binary is not found
- **THEN** a label "GitHub Copilot CLI not found" is shown with installation instructions

#### Scenario: GitHub Copilot section — not logged in
- **WHEN** user opens the API Keys tab and the CLI is installed but no keychain token exists
- **THEN** a warning "Not logged in" is shown with instructions to run `copilot login`

#### Scenario: Engine picker hides Copilot when unavailable
- **WHEN** user opens the engine picker in the Preferences tab and Copilot CLI is not installed or not logged in
- **THEN** the "GitHub Copilot" option is not shown in the picker
