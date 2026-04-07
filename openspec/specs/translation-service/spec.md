## Purpose

Translation backends and protocol for converting detected manga text between languages.

## Requirements

### Requirement: Unified translation protocol
The system SHALL define a `TranslationService` protocol that all translation backends conform to. The protocol SHALL accept an array of bubble texts (with positions) and return an array of translations. All backends receive the full page context.

#### Scenario: Protocol conformance
- **WHEN** a new translation backend is added
- **THEN** it conforms to the `TranslationService` protocol and can be used interchangeably

### Requirement: Support DeepL translation backend
The system SHALL support DeepL API as a translation backend. DeepL SHALL translate each bubble independently via the DeepL REST API.

#### Scenario: DeepL translates Japanese to Traditional Chinese
- **WHEN** user selects DeepL engine and translates a page from Japanese to Traditional Chinese
- **THEN** each bubble is sent to DeepL API and the translated text is returned

### Requirement: Support Google Translate backend
The system SHALL support Google Cloud Translation API as a translation backend.

#### Scenario: Google translates English to Japanese
- **WHEN** user selects Google engine and translates a page from English to Japanese
- **THEN** each bubble is sent to Google Cloud Translation API and the translated text is returned

### Requirement: Support OpenAI LLM translation backend
The system SHALL support OpenAI API (GPT models) as a translation backend. The system SHALL send all bubbles on a page in a single request with positional context and a system prompt instructing manga-style translation. The user prompt SHALL use each bubble's original `bubble.index` (not enumeration offset) as the `index` field. The system prompt SHALL instruct the LLM to echo back the `index` field exactly as given without reordering. The system prompt SHALL additionally include glossary terms and recent page context. The response SHALL be in JSON format with the extended `detected_terms` field.

#### Scenario: OpenAI translates full page with context
- **WHEN** user selects OpenAI engine and translates a page with 5 bubbles
- **THEN** all 5 bubbles are sent in one API call with position data, and a JSON array of translations is returned with the same indices as received

#### Scenario: OpenAI respects active glossary
- **WHEN** an active glossary is set and user translates with OpenAI engine
- **THEN** the system prompt includes the glossary terms and the response honours them

#### Scenario: OpenAI index echoed back unchanged
- **WHEN** bubbles with indices [0, 2, 3] are sent (after punctuation filtering)
- **THEN** the response contains exactly indices [0, 2, 3], not [0, 1, 2]

### Requirement: Six translation directions
The system SHALL support translation between any pair of: Japanese (ja), English (en), Traditional Chinese (zh-Hant). This includes all six directed pairs.

#### Scenario: All language pairs available
- **WHEN** user opens the language selection UI
- **THEN** source and target language dropdowns each contain Japanese, English, and Traditional Chinese, and any combination is selectable (except same source and target)

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

### Requirement: LLM JSON response parsing with retry
The system SHALL parse LLM translation responses as JSON arrays. The parser SHALL use a dictionary keyed by `bubble.index` to match response items to original bubbles, rather than using the index as a direct array offset. If parsing fails, the system SHALL retry the request up to 2 times. If all retries fail, the system SHALL fall back to line-by-line text parsing.

#### Scenario: Malformed JSON response
- **WHEN** the LLM returns invalid JSON on first attempt
- **THEN** the system retries, and if the retry returns valid JSON, uses that result

#### Scenario: All retries fail
- **WHEN** the LLM returns invalid JSON on all 3 attempts
- **THEN** the system falls back to splitting the response by newlines and matching to bubbles by position

#### Scenario: Parser uses dictionary lookup
- **WHEN** LLM returns an index value that was in the original request
- **THEN** the parser maps it to the correct bubble using dictionary lookup, not array indexing

#### Scenario: Parser ignores unknown indices
- **WHEN** LLM returns an index value not present in the original request
- **THEN** the parser silently drops that item and continues processing remaining items
