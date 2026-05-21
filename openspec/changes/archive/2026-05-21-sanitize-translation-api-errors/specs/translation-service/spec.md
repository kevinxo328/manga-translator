## ADDED Requirements

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
