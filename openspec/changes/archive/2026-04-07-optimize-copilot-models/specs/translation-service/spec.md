## MODIFIED Requirements

### Requirement: Support GitHub Copilot translation backend
The system SHALL support GitHub Copilot as a translation backend. The engine SHALL read the OAuth token from the local keychain entry stored by the Copilot CLI (`copilot-cli` service). The engine SHALL call `api.individual.githubcopilot.com` (for Individual accounts) or `api.githubcopilot.com` (for Business/Enterprise accounts) using the OpenAI-compatible chat completions endpoint with the `Copilot-Integration-Id: vscode-chat` header and `X-GitHub-Api-Version: 2022-11-28` header. The engine SHALL use the same LLM prompt, JSON parsing, and retry logic as the OpenAI backend. If the Copilot CLI is not installed or not logged in, the system SHALL throw `TranslationError.missingAPIKey(.githubCopilot)`.

#### Scenario: Copilot CLI present and logged in
- **WHEN** user selects GitHub Copilot engine and translates a page
- **THEN** the system reads the OAuth token from keychain and calls `api.individual.githubcopilot.com/chat/completions` (or `api.githubcopilot.com/chat/completions`)
- **THEN** translated bubbles are returned

#### Scenario: Copilot CLI not installed
- **WHEN** user selects GitHub Copilot engine but the `copilot` binary is not found in PATH
- **THEN** the system throws `TranslationError.missingAPIKey(.githubCopilot)`

#### Scenario: Copilot CLI installed but not logged in
- **WHEN** the `copilot` binary exists but no keychain token is present
- **THEN** the system throws `TranslationError.missingAPIKey(.githubCopilot)`
