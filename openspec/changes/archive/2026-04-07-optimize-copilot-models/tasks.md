## 1. Data Model & Types

- [x] 1.1 Define `CopilotModel` struct and parsing logic in `Models.swift`.
- [x] 1.2 Update `CopilotAvailability` or state to handle the model list.

## 2. API & Environment Logic

- [x] 2.1 Refactor `CopilotEnvironment.fetchModels`: Update headers (`vscode-chat`, `X-GitHub-Api-Version`).
- [x] 2.2 Implement model filtering and parsing: Include `chat_completions` only and parse `multiplier`.
- [x] 2.3 Implement dual endpoint switching for Individual and Enterprise domains.
- [x] 2.4 Write tests for the new model fetching logic.

## 3. UI & ViewModel Integration

- [x] 3.1 Update `TranslationViewModel` to handle the transition from `[String]` to `[CopilotModel]`.
- [x] 3.2 Update `TranslationSidebar.swift`: Format model names and multipliers (e.g., `Claude Sonnet 4.5 (1x)`).
- [x] 3.3 Ensure correct preference storage and UI state when switching models.

## 4. Verification

- [x] 4.1 Mock API with various multipliers (0x, 0.33x, 1x, 3x) to verify UI display.
- [x] 4.2 Verify default multiplier (1x) when missing from API.
- [x] 4.3 Run integration tests to ensure translation remains functional.
