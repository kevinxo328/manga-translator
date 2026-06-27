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
The system SHALL support GitHub Copilot as a translation backend. It SHALL read the OAuth token from the local keychain entry stored by the Copilot CLI (`copilot-cli` service). It SHALL call `api.individual.githubcopilot.com` first and use `api.githubcopilot.com` only under the bounded fallback rules. Copilot model, model-session, and Auto inference requests SHALL use `Copilot-Integration-Id: copilot-developer-cli`; model-session-aware requests SHALL use `X-GitHub-Api-Version: 2026-07-01`.

For the `auto` selection, the engine SHALL perform the compatibility-filtered model-session protocol and send the resolved model plus `Copilot-Session-Token` to `/chat/completions`. For an explicit selection, the engine SHALL verify that the current catalog exposes that model as picker-enabled and `/chat/completions`-compatible, then call `/chat/completions` without an Auto session token. The engine SHALL use the same prompt construction, JSON parsing, parser retry, and batch behavior as the OpenAI backend. If the Copilot CLI is not installed or logged in, the system SHALL throw `TranslationError.missingAPIKey(.githubCopilot)`.

#### Scenario: Copilot Auto translates through a concrete model
- **WHEN** the CLI is installed and logged in, the saved selection is `auto`, and the user translates a page
- **THEN** the engine resolves a compatible concrete model on the individual host
- **AND** it sends that model and the Copilot session token to the individual host's `/chat/completions`
- **AND** translated bubbles are returned through the existing response parser

#### Scenario: Explicit compatible model translates directly
- **WHEN** the saved selection identifies a picker-enabled model advertising `/chat/completions`
- **THEN** the engine sends that concrete model to `/chat/completions`
- **AND** it does not acquire or send an Auto session token

#### Scenario: Explicit unavailable model is not silently replaced
- **WHEN** the saved explicit model is absent, picker-disabled, or lacks `/chat/completions` support
- **THEN** translation fails with an actionable model-unavailable error
- **AND** the service does not silently select Auto or another concrete model

#### Scenario: Copilot CLI not installed
- **WHEN** user selects GitHub Copilot but the `copilot` binary is not found in PATH
- **THEN** the system throws `TranslationError.missingAPIKey(.githubCopilot)`

#### Scenario: Copilot CLI installed but not logged in
- **WHEN** the `copilot` binary exists but no keychain token is present
- **THEN** the system throws `TranslationError.missingAPIKey(.githubCopilot)`

### Requirement: LLM JSON response parsing with retry
The system SHALL parse LLM translation responses as JSON arrays. The parser SHALL use a dictionary keyed by `bubble.index` to match response items to original bubbles, rather than using the index as a direct array offset. If parsing fails, the system SHALL retry the request once, for a total of 2 attempts. If both attempts fail, the system SHALL fall back to line-by-line text parsing.

#### Scenario: Malformed JSON response
- **WHEN** the LLM returns invalid JSON on first attempt
- **THEN** the system retries, and if the retry returns valid JSON, uses that result

#### Scenario: All retries fail
- **WHEN** the LLM returns invalid JSON on both attempts
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

### Requirement: Resolve Copilot Auto through a model session
When the persisted Copilot selection is `auto`, the system SHALL resolve a concrete chat-completions-compatible model before inference. For each host, it SHALL fetch or reuse the model catalog, derive ordered hints only from models advertising `/chat/completions`, and call `<host>/models/session` with those hints. The system SHALL NOT send `model: "auto"` to any inference endpoint.

The model-session request SHALL include OAuth authorization, `Content-Type: application/json`, `Copilot-Integration-Id: copilot-developer-cli`, and `X-GitHub-Api-Version: 2026-07-01`. A valid response SHALL contain a nonempty `selected_model`, nonempty `session_token`, and `available_models` containing the selected model. The selected model SHALL also belong to the submitted compatible hint set. When `expires_at` is present, it SHALL decode to a time strictly later than the validation clock. When it is absent, the session SHALL be valid for the immediate inference but SHALL NOT be cached. A present invalid or nonfuture expiry SHALL invalidate the response.

#### Scenario: Auto resolves to a compatible model
- **WHEN** the user translates with Copilot selection `auto`
- **AND** `/models` advertises `gpt-5-mini` for `/chat/completions` and `gpt-5.3-codex` only for `/responses`
- **THEN** `/models/session` receives a hint set containing `gpt-5-mini` but not `gpt-5.3-codex`
- **AND** inference sends the returned concrete model identifier rather than `auto`

#### Scenario: Auto inference carries the session token
- **WHEN** `/models/session` resolves a valid concrete model and session token
- **THEN** the following `/chat/completions` request includes `Copilot-Session-Token` with that token
- **AND** it includes the Copilot integration ID and API version headers

#### Scenario: No compatible Auto hints
- **WHEN** the model catalog contains no model supporting `/chat/completions`
- **THEN** translation fails before calling `/models/session` or `/chat/completions`
- **AND** the error identifies that no compatible Copilot model is available

#### Scenario: Invalid model-session response
- **WHEN** the model-session response omits a required non-expiry field, has a present invalid or nonfuture expiry, selects a model absent from `available_models`, or selects a model outside the submitted hint set
- **THEN** the response is rejected as a protocol failure
- **AND** no inference request is sent on that host

#### Scenario: Missing expiry is noncacheable
- **WHEN** an otherwise valid model-session response omits `expires_at`
- **THEN** its model and session token are used only for the immediate inference
- **AND** the session is not stored in the resolver cache
- **AND** the next translation performs a new model-session request

### Requirement: Cache and refresh Copilot Auto sessions safely
The system SHALL keep resolved Auto sessions in process memory only. A cached session SHALL be keyed by the same host, authenticated-account token digest, and ordered compatible hint set. Observing a different account digest for one host SHALL evict that host's prior session entries and invalidate their in-flight work. Observing a different hint sequence for the same host/account SHALL evict the prior hint-key session. Expired entries SHALL be removed before lookup. OAuth tokens, session tokens, and token-derived cache keys SHALL NOT be persisted, displayed, or logged.

When a cached session has more than five minutes remaining, it SHALL be reused. When it is unexpired with five minutes or less remaining, the system SHALL refresh it before inference by calling the same host's `POST /models/session` with the same model hints and the old token in `Copilot-Session-Token`. When it is expired, the system SHALL discard it and perform initial acquisition without an old session header. Acquisition and refresh responses SHALL use the same validation rules, and a successful expiring replacement of selected model, token, and expiry SHALL be atomic. A successful replacement without expiry SHALL remove the old cached entry and remain immediate-use-only.

#### Scenario: Refresh without expiry removes cached state
- **WHEN** an otherwise valid refresh response omits `expires_at`
- **THEN** its new model and token are used for the immediate inference
- **AND** the old cached session is removed
- **AND** the new session is not cached

Concurrent requests for the same key SHALL share one in-flight acquisition or refresh. Cancellation of one waiting caller SHALL NOT cancel shared work needed by other callers. An invalidated in-flight result SHALL NOT repopulate the cache after it completes.

#### Scenario: Batch requests share a valid Auto session
- **WHEN** multiple page or batch translation calls concurrently need the same fresh Auto session
- **THEN** exactly one `/models/session` acquisition is performed
- **AND** each inference request uses the same resolved model and session token

#### Scenario: Fresh cached session is reused
- **WHEN** a later translation uses the same host, account, and hint set before the five-minute refresh boundary
- **THEN** the cached session is used without another `/models/session` request

#### Scenario: Nearly expired session is refreshed
- **WHEN** the cached session expires in five minutes or less
- **AND** the cached session is still unexpired
- **THEN** the next translation calls the same host's `/models/session` before inference
- **AND** the refresh request includes the old token in `Copilot-Session-Token`
- **AND** it sends the same ordered compatible model hints

#### Scenario: Refresh can select a different compatible model
- **WHEN** a valid refresh response selects a different model within both `available_models` and the submitted compatible hint set
- **AND** it contains a valid future expiry
- **THEN** the cache atomically replaces the prior model, session token, and expiry
- **AND** inference uses the new model and token

#### Scenario: Expired session uses initial acquisition
- **WHEN** the cached session has reached or passed `expires_at`
- **THEN** it is discarded
- **AND** the next `/models/session` request does not include `Copilot-Session-Token`

#### Scenario: Refresh unauthorized retries without the old session
- **WHEN** refresh returns HTTP 401
- **THEN** the old session is discarded
- **AND** the system performs exactly one initial acquisition without `Copilot-Session-Token`
- **AND** a 401 or 403 from that acquisition is surfaced as a terminal OAuth authorization failure

#### Scenario: Transient refresh failure reuses only an unexpired session
- **WHEN** refresh fails with a non-cancellation transport error or HTTP 5xx
- **AND** the old session remains strictly unexpired after the failure
- **THEN** the current inference SHALL use the old model and session token
- **WHEN** the old session is expired after the failure
- **THEN** it is not used for inference

#### Scenario: Refresh rate limit is terminal
- **WHEN** refresh returns HTTP 429
- **THEN** the sanitized rate-limit error is surfaced
- **AND** the old session is not used to bypass the rate limit
- **AND** no alternate host is attempted

#### Scenario: Account or hint set changes
- **WHEN** the OAuth account identity, host, or ordered compatible hint set differs from the cached session
- **THEN** the cached session is not reused
- **AND** the old session token is not sent in the new request
- **AND** a changed account on the same host or changed hint set for the same host/account evicts the superseded session entry

#### Scenario: Concurrent callers share refresh
- **WHEN** multiple callers need the same nearly expired session concurrently
- **THEN** exactly one refresh request is issued
- **AND** all non-cancelled callers receive the same validated replacement session

#### Scenario: Invalidation wins over an older in-flight refresh
- **WHEN** a session key is invalidated while its refresh is in flight
- **THEN** completion of that older refresh does not restore the invalidated cache entry

### Requirement: Bound Copilot Auto recovery and host fallback
Auto catalog lookup, session acquisition, and inference SHALL form one host-local transaction. The system SHALL try `api.individual.githubcopilot.com` before `api.githubcopilot.com`; it SHALL NOT reuse a catalog or session token across hosts. Cancellation SHALL propagate immediately. OAuth authorization failures and rate limits SHALL propagate without host fallback or arbitrary model substitution.

When Auto inference fails with `model_not_supported` or `unsupported_api_for_model`, the system SHALL invalidate matching catalog and session state, fetch a new catalog, acquire a new session without an old session header, and perform at most one recovery inference. When Auto inference returns HTTP 401, the system SHALL invalidate the session only, acquire once without an old session header, and perform the recovery inference only if acquisition succeeds. A 401/403 during that acquisition SHALL be terminal OAuth failure. All Auto recovery causes SHALL share one per-translation recovery budget, so an error sequence cannot trigger more than one recovery inference. A repeated failure SHALL surface through the sanitized provider error contract.

The shared chat-completions retry loop SHALL expose Copilot API errors to this state machine without first repeating a nonretryable inference request. For Copilot, only transport failures and HTTP 5xx SHALL be API-retry-eligible inside the existing two-attempt client loop. HTTP 401, 403, 429, every other 4xx, `model_not_supported`, and `unsupported_api_for_model` SHALL leave that loop after the first inference request. Response parse failures SHALL retain the existing two-attempt behavior. Other providers SHALL retain their existing retry behavior.

#### Scenario: Individual Auto protocol falls back to business host
- **WHEN** the individual host has a non-cancellation network failure, HTTP 404, HTTP 5xx, malformed successful protocol response, or unavailable Auto protocol
- **THEN** the system starts a fresh catalog-session-inference transaction on the business host
- **AND** no individual-host session token is sent to the business host

#### Scenario: Individual catalog has no compatible Auto model
- **WHEN** the individual host returns a decoded nonempty catalog with no `/chat/completions`-compatible model
- **THEN** the system fetches the business-host catalog
- **AND** a compatible business catalog owns a fresh business-host session and inference transaction

#### Scenario: Explicit model is available only on the business host
- **WHEN** an explicit saved model is absent, picker-disabled, or incompatible on the individual host
- **AND** the business host exposes that model as picker-enabled and `/chat/completions`-compatible
- **THEN** the explicit translation uses the business host without an Auto session token

#### Scenario: Explicit model is unavailable on both hosts
- **WHEN** neither host exposes the explicit saved model as picker-enabled and `/chat/completions`-compatible
- **THEN** translation fails with the actionable model-unavailable error
- **AND** the service does not silently select Auto or another concrete model

#### Scenario: Explicit inference failure falls back as a complete transaction
- **WHEN** the individual host exposes the explicit compatible model but its inference exhausts a fallback-eligible failure
- **THEN** the service fetches and validates the business catalog before business inference
- **AND** the business request does not contain a Copilot Auto session token

#### Scenario: Stale Auto selection is recovered once
- **WHEN** Auto inference returns `model_not_supported`
- **THEN** matching catalog and session state are invalidated
- **AND** the system resolves and retries inference once
- **AND** a second `model_not_supported` error is surfaced without another resolution

#### Scenario: Recoverable model error is not duplicated by the client retry loop
- **WHEN** Auto inference returns `model_not_supported` or `unsupported_api_for_model`
- **THEN** the same model and session request is not repeated by `ChatCompletionsClient`
- **AND** control returns immediately to the bounded Auto recovery state machine

#### Scenario: Responses-only selection is recovered once
- **WHEN** inference returns `unsupported_api_for_model`
- **THEN** the system invalidates state and performs one new compatibility-filtered resolution
- **AND** it never switches the current client to `/responses`

#### Scenario: Auto inference 401 distinguishes session from OAuth failure
- **WHEN** Auto inference returns HTTP 401
- **THEN** the current session is invalidated
- **AND** exactly one initial session acquisition is attempted without the old token
- **AND** successful acquisition permits one recovery inference
- **AND** acquisition HTTP 401/403 is surfaced without recovery inference or host fallback

#### Scenario: Recovery budget is shared across error types
- **WHEN** one translation has already performed a recovery inference for any Auto recovery cause
- **AND** that recovery inference fails with another recoverable Auto error
- **THEN** the second error is surfaced
- **AND** no additional catalog fetch, session acquisition, or inference recovery is performed

#### Scenario: Cancellation does not retry or fall back
- **WHEN** catalog loading, session acquisition, or inference is cancelled
- **THEN** cancellation propagates immediately
- **AND** no retry or alternate-host request is made

#### Scenario: OAuth authorization failure does not change host
- **WHEN** a Copilot protocol request returns an OAuth authorization failure
- **THEN** the sanitized authorization error is surfaced
- **AND** the business host is not attempted with the same invalid credential

#### Scenario: Rate limit does not select an arbitrary model
- **WHEN** Copilot returns a rate-limit response
- **THEN** the sanitized rate-limit error is surfaced
- **AND** the system does not bypass Auto by choosing a concrete model itself
- **AND** the system does not retry on the business host
- **AND** the same inference request is not repeated by the chat-completions retry loop

#### Scenario: Ordinary transient and parse retries remain unchanged
- **WHEN** Copilot inference has a transport failure or HTTP 5xx
- **THEN** the existing two-attempt chat-completions retry budget applies
- **WHEN** a successful Copilot response cannot be parsed
- **THEN** the existing parse retry and line-based fallback behavior applies

### Requirement: Log Copilot Auto routing without credentials
The system SHALL log the resolved concrete Auto model and sanitized host endpoint as operational diagnostics. It SHALL NOT log OAuth tokens, Copilot session tokens, token fingerprints, model-session request or response bodies, inference request bodies, or raw provider error bodies.

#### Scenario: Successful Auto resolution is diagnosable
- **WHEN** Auto resolves a concrete model
- **THEN** the debug log records the concrete model identifier and sanitized endpoint
- **AND** it contains no OAuth or session-token material

#### Scenario: Model-session failure remains sanitized
- **WHEN** the model-session endpoint returns an error body containing credential-like material
- **THEN** user-visible and persistent errors follow the existing provider sanitization contract
- **AND** the raw response body is not stored or logged
