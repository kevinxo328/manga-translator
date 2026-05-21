## ADDED Requirements

### Requirement: Persist sanitized provider API error diagnostics
The system SHALL allow translation provider API error diagnostics to be persisted only as sanitized structured operational logs. A persisted provider API error diagnostic SHALL include provider category, HTTP status code, safe machine-readable code when available, redacted provider message when available, model when applicable, and sanitized endpoint when available.

The system SHALL NOT persist raw provider response bodies, authorization header values, API keys, OAuth tokens, bearer tokens, query secrets, email addresses, request bodies, or full response payloads as part of provider API error diagnostics. Sanitized provider messages persisted in logs SHALL use the same redaction and 200-character message bound as UI-facing provider API errors.

#### Scenario: Provider error log keeps redacted provider message
- **WHEN** a translation provider returns a non-2xx response with a provider error message and code
- **THEN** the persistent debug log SHALL include the provider category, HTTP status code, safe code, and redacted provider message
- **AND** the persistent debug log SHALL NOT include the raw response body

#### Scenario: Provider error log removes credentials and personal identifiers
- **WHEN** a translation provider error response contains an authorization header value, API key, OAuth token, bearer token, URL query secret, long opaque token-like string, or email address
- **THEN** the persistent debug log SHALL omit or replace those sensitive values
- **AND** the persistent debug log SHALL preserve the non-sensitive error semantics needed to diagnose the failure

#### Scenario: Provider error endpoint is sanitized
- **WHEN** a provider API error diagnostic includes an endpoint with embedded credentials, query parameters, or a fragment
- **THEN** the persisted endpoint metadata SHALL remove embedded credentials, query parameters, and fragment

#### Scenario: Raw body metadata remains disallowed
- **WHEN** a call site attempts to log provider error response content under metadata keys such as response body, raw response, payload, token, secret, or authorization
- **THEN** the persisted metadata SHALL redact those values
