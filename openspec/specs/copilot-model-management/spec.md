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
