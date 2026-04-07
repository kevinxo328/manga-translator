## Context

Currently, `CopilotEnvironment.fetchModels` only returns `[String]` and has very simple filtering logic. With GitHub Copilot's Premium Multiplier mechanism, the existing implementation cannot meet the need for displaying multiplier info or accurately filtering non-chat models.

## Goals / Non-Goals

**Goals:**
- Provide structured `CopilotModel` data (ID, friendly name, multiplier).
- Simulate official VS Code/CLI environment API behavior for a consistent model list.
- Clearly display multipliers in the UI to help users evaluate translation costs.
- Accurately filter models supporting `chat_completions`.

**Non-Goals:**
- Do not modify OAuth flows (reuse existing Keychain access).
- Do not support multiplier display for non-Copilot translation backends.

## Decisions

### 1. Structured Model Definition
- **Decision**: Create a `CopilotModel` struct in `Models.swift`.
- **Rationale**: Replaces raw `String` arrays for richer data and type safety.
- **Alternatives**: Continue using `String` and manually parse (e.g., `id:multiplier`), but this increases parsing complexity and maintenance difficulty.

### 2. Update API Headers
- **Decision**: Use `Copilot-Integration-Id: vscode-chat` and `X-GitHub-Api-Version: 2022-11-28`.
- **Rationale**: `vscode-chat` is the most stable integration ID for full feature descriptions. Specifying the API version ensures a consistent `multiplier` field format.
- **Alternatives**: Use `gh-copilot`, but `vscode-chat` is better validated for compatibility.

### 3. Dynamic Endpoint Switching
- **Decision**: Prefer `api.individual.githubcopilot.com`, then fallback/switch to `api.githubcopilot.com` if failure or enterprise permissions are detected.
- **Rationale**: Ensures both individual and enterprise users see the correct model list.

## Risks / Trade-offs

- **[Risk] API Format Changes** → **Mitigation**: Provide a default multiplier (1.0x) and robust error handling to ensure model loading doesn't fail if multiplier parsing fails.
- **[Trade-off] Data Storage Complexity** → **Mitigation**: `PreferencesService` will continue to store only the chosen model `id` (String), while dynamic info (name, multiplier) is updated on each fetch.
