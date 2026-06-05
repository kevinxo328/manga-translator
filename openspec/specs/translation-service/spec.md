## Purpose

Translation backends and protocol for converting detected manga text between languages.

## Requirements

### Requirement: Unified translation protocol
The system SHALL define a `TranslationService` protocol that all translation backends conform to. The protocol SHALL accept an array of bubble texts (with positions) and return an array of translations. All backends receive the full page context.

#### Scenario: Protocol conformance
- **WHEN** a new translation backend is added
- **THEN** it conforms to the `TranslationService` protocol and can be used interchangeably

### Requirement: Support DeepL translation backend
The system SHALL support DeepL API as a translation backend. DeepL SHALL translate each bubble independently via the DeepL REST API. DeepL language-code mapping SHALL support every language in the target language list.

#### Scenario: DeepL translates Japanese to Traditional Chinese
- **WHEN** user selects DeepL engine and translates a page from Japanese to Traditional Chinese
- **THEN** each bubble is sent to DeepL API and the translated text is returned

#### Scenario: DeepL maps expanded target languages
- **WHEN** user selects any supported target language
- **THEN** DeepL requests SHALL use the provider language code for that target language

### Requirement: Support Google Translate backend
The system SHALL support Google Cloud Translation API as a translation backend. Google language-code mapping SHALL support every language in the target language list.

#### Scenario: Google translates English to Japanese
- **WHEN** user selects Google engine and translates a page from English to Japanese
- **THEN** each bubble is sent to Google Cloud Translation API and the translated text is returned

#### Scenario: Google maps expanded target languages
- **WHEN** user selects any supported target language
- **THEN** Google Translate requests SHALL use the provider language code for that target language

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

### Requirement: Supported translation languages
The system SHALL support English and Japanese as source languages. The system SHALL support English, French, German, Indonesian, Japanese, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, Traditional Chinese, and Vietnamese as target languages. Source and target language lists SHALL be sorted A-Z by English display name. Any valid combination SHALL be selectable, including same-language pairs; same-language execution behavior is owned by the pipeline skip optimization capability.

#### Scenario: All language pairs available
- **WHEN** user opens the language selection UI
- **THEN** the source language dropdown contains English and Japanese in that order
- **AND** the target language dropdown contains English, French, German, Indonesian, Japanese, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, Traditional Chinese, and Vietnamese in that order

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

### Requirement: Sanitized provider API error contract
The system SHALL represent translation provider non-2xx HTTP responses as structured sanitized API errors. A sanitized API error SHALL include the translation provider display name, HTTP status code, an optional machine-readable code, and an optional sanitized message. The raw provider response body SHALL NOT be stored in `TranslationError`, exposed through `localizedDescription`, or written into page error state.

The UI-facing description for a sanitized provider API error SHALL use these formats:

- `<Provider> request failed with HTTP <status> (<code>): <sanitized message>` when code and message are present
- `<Provider> request failed with HTTP <status>: <sanitized message>` when only message is present
- `<Provider> request failed with HTTP <status>` when no safe message is available

The sanitized message SHALL be at most 200 characters after redaction. Sanitization SHALL remove or replace authorization header values, API keys, OAuth tokens, bearer tokens, long opaque token-like strings, URL query secrets, and email addresses. If redaction leaves no useful message, the message SHALL be omitted.

#### Scenario: Provider body does not reach page error UI
- **WHEN** a translation provider returns a non-2xx response body containing an API key, email address, authorization header, or query secret
- **THEN** the page error state SHALL contain a provider API error summary with provider and HTTP status
- **AND** the page error state SHALL NOT contain the raw API key, email address, authorization header value, query secret, or full raw response body

#### Scenario: Provider API error includes safe code and message
- **WHEN** a translation provider returns a non-2xx response with parseable code and message fields
- **THEN** the UI-facing error SHALL include the provider display name, HTTP status code, safe machine-readable code, and sanitized message

#### Scenario: Provider API error omits unsafe empty message
- **WHEN** a translation provider returns a non-2xx response whose message is empty after sanitization
- **THEN** the UI-facing error SHALL include the provider display name and HTTP status code
- **AND** the UI-facing error SHALL NOT include an empty colon suffix or raw body fallback

#### Scenario: Existing non-provider errors keep their current bridge
- **WHEN** translation fails because of missing credentials, invalid success-body parsing, transport failure, OCR failure, cache failure, archive import failure, or model lifecycle failure
- **THEN** the system SHALL preserve the existing non-provider error bridge unless that error is a provider non-2xx HTTP response

### Requirement: Provider-specific API error parsing
The system SHALL parse non-2xx translation provider response bodies using provider-specific best-effort rules before creating a sanitized API error.

OpenAI Compatible SHALL read code from `error.code`, then `error.type`, and message from `error.message`. GitHub Copilot SHALL use the OpenAI-compatible rules first, then read top-level `code` and top-level `message` as fallbacks. Google Translate SHALL read code from `error.status`, then the first `error.errors[].reason`, then numeric `error.code` converted to a string, and message from `error.message`. DeepL SHALL read message from top-level `message` and SHALL read code only when a string `code` field is present. Generic fallback parsing SHALL read top-level `code` or `error_code`, then message from top-level `message`, `error_description`, or sanitized body text.

Parsing failures SHALL NOT throw a secondary parsing error. If no parseable code or message exists, the sanitized API error SHALL still include provider and HTTP status.

#### Scenario: OpenAI-compatible error is parsed
- **WHEN** OpenAI Compatible returns a non-2xx body with `error.message`, `error.type`, and `error.code`
- **THEN** the sanitized API error SHALL use `error.code` when present
- **AND** the sanitized API error SHALL use `error.message` after redaction and truncation

#### Scenario: Copilot error uses OpenAI-compatible fallback
- **WHEN** GitHub Copilot returns a non-2xx body with an OpenAI-compatible `error.message` and `error.code`
- **THEN** the sanitized API error SHALL use the same code and message extraction rules as OpenAI Compatible

#### Scenario: Google error uses stable status or reason
- **WHEN** Google Translate returns a non-2xx body with `error.status`, `error.errors[].reason`, `error.code`, and `error.message`
- **THEN** the sanitized API error SHALL prefer `error.status` as the code
- **AND** the sanitized API error SHALL use `error.message` after redaction and truncation

#### Scenario: DeepL error uses message key
- **WHEN** DeepL returns a non-2xx body with a top-level `message`
- **THEN** the sanitized API error SHALL use that message after redaction and truncation

#### Scenario: Unparseable body falls back safely
- **WHEN** a translation provider returns a non-2xx response body that is not valid JSON
- **THEN** the sanitized API error SHALL include provider and HTTP status
- **AND** the sanitized API error MAY include a redacted and truncated text message from the response body
- **AND** the raw response body SHALL NOT be exposed

### Requirement: Translation services throw only sanitized provider API errors
OpenAI Compatible, GitHub Copilot, Google Translate, and DeepL translation services SHALL throw `TranslationError.apiError` only with a structured sanitized API error for provider non-2xx HTTP responses. Translation services SHALL NOT construct provider API errors from raw response-body strings.

Translation service HTTP clients SHALL support deterministic test injection of URL loading behavior while preserving `.shared` session behavior for production callers.

#### Scenario: OpenAI-compatible non-2xx throws sanitized API error
- **WHEN** OpenAI Compatible receives a non-2xx HTTP response
- **THEN** it SHALL throw `TranslationError.apiError` with a sanitized API error payload
- **AND** it SHALL NOT throw an API error containing the raw response body string

#### Scenario: Copilot non-2xx throws sanitized API error
- **WHEN** GitHub Copilot receives a non-2xx HTTP response
- **THEN** it SHALL throw `TranslationError.apiError` with a sanitized API error payload
- **AND** it SHALL NOT throw an API error containing the raw response body string

#### Scenario: DeepL and Google non-2xx throw sanitized API errors
- **WHEN** DeepL or Google Translate receives a non-2xx HTTP response
- **THEN** the service SHALL throw `TranslationError.apiError` with a sanitized API error payload
- **AND** the service SHALL NOT expose the raw response body through `localizedDescription`
