## Purpose

Fetching, filtering, and displaying the list of available GitHub Copilot models in the model selection UI.
## Requirements
### Requirement: Structured Copilot Model data
The system SHALL define a `CopilotModel` structure to store information about GitHub Copilot models, including their unique identifier, display name, and picker category.

#### Scenario: CopilotModel structure
- **WHEN** a `CopilotModel` is instantiated
- **THEN** it contains `id`, `name`, and `category` (optional String)

### Requirement: Filtered model fetching
The system SHALL fetch the list of available models from GitHub Copilot API and include only models where `model_picker_enabled` is `true`. The system SHALL try `api.individual.githubcopilot.com` first, then fall back to `api.githubcopilot.com` if the first endpoint returns no results.

#### Scenario: Fetching and filtering picker-enabled models
- **WHEN** `CopilotEnvironment.fetchModels` is called
- **THEN** it sends a request with `Copilot-Integration-Id: vscode-chat` and `X-GitHub-Api-Version: 2022-11-28`
- **THEN** it returns only models where `model_picker_enabled == true`
- **THEN** results are sorted alphabetically by name

#### Scenario: Dual endpoint fallback
- **WHEN** `api.individual.githubcopilot.com` returns no models or errors
- **THEN** the system retries against `api.githubcopilot.com`

### Requirement: Display model category in UI
The system SHALL display the model name followed by a human-readable category label in the selection UI. The label is derived from the `model_picker_category` field returned by the API.

#### Scenario: Displaying model name and category
- **WHEN** the user opens the model selection dropdown
- **THEN** each item shows the friendly name and category label, e.g.:
  - `"powerful"` → `"Claude Opus 4.5 (Premium)"`
  - `"versatile"` → `"Claude Sonnet 4.5 (Standard)"`
  - `"lightweight"` → `"GPT-5 mini (Lite)"`
  - no category → model name only

### Requirement: Copilot model selection persistence
The system SHALL persist the user's Copilot model selection to `UserDefaults` under the key `copilotModel`. The selection SHALL be restored on subsequent app launches. The default value when no preference has been saved SHALL be `gpt-5-mini`. Subsequent translations using the GitHub Copilot engine SHALL use the persisted model identifier.

#### Scenario: User selects a GitHub Copilot model
- **WHEN** the Copilot CLI is available and user picks a model from the Copilot model picker
- **THEN** the selection is persisted to `copilotModel` in UserDefaults
- **THEN** subsequent translations using the GitHub Copilot engine use the selected model

#### Scenario: App restart preserves Copilot model choice
- **WHEN** the user selects a Copilot model and restarts the app
- **THEN** the previously selected model is shown in the picker
- **THEN** translations use the previously selected model

#### Scenario: Default Copilot model on first launch
- **WHEN** no `copilotModel` preference has been saved
- **THEN** the active Copilot model is `gpt-5-mini`

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

