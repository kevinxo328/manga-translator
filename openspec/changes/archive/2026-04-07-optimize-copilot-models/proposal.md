## Why

The current GitHub Copilot model fetching logic is too simplistic, filtering only models starting with `text-embedding`. This results in a cluttered list containing non-chat models and lacks Premium Multiplier information. Users cannot see the point consumption for specific models (e.g., Claude 3.5 Sonnet or o1).

## What Changes

- Update GitHub Copilot API headers to use `vscode-chat` as the integration ID and specify the API version for consistency with official IDEs.
- Parse the `multiplier` or `policy_multiplier` field from the model response.
- Improve model filtering logic to include only models with the `chat_completions` capability.
- Display the model name and its corresponding multiplier in the UI model selection (e.g., `Claude 3.5 Sonnet (1x)`).

## Capabilities

### New Capabilities
- `copilot-model-management`: Handles fetching, parsing, filtering, and multiplier display for Copilot models.

### Modified Capabilities
- `translation-service`: Updates the GitHub Copilot translation backend to support structured model info and multiplier display.

## Impact

- `CopilotEnvironment.swift`: Refactor model fetching and filtering logic.
- `Models.swift`: Add `CopilotModel` struct.
- `TranslationSidebar.swift`: Update UI to display multiplier information.
- `PreferencesService.swift`: May need updates to store more complete model information.
