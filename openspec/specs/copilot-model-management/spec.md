## Purpose

Fetching, filtering, and displaying the list of available GitHub Copilot models in the model selection UI.
## Requirements
### Requirement: Structured Copilot Model data
The system SHALL define a `CopilotModel` structure containing the model's unique identifier, display name, optional picker category, optional picker-enabled flag, supported endpoint set, and optional capability type. The structure SHALL expose derived behavior for exact `/chat/completions` compatibility and display labeling without conflating picker visibility with transport compatibility.

#### Scenario: CopilotModel structure
- **WHEN** a `CopilotModel` is decoded from the Copilot model API
- **THEN** it contains `id`, `name`, `category`, `pickerEnabled`, `supportedEndpoints`, and `capabilityType`

#### Scenario: Missing optional metadata
- **WHEN** optional picker, category, capability, or endpoint fields are absent
- **THEN** decoding succeeds with optional or empty values
- **AND** missing endpoint metadata does not grant transport compatibility

### Requirement: Filtered model fetching
The system SHALL fetch a complete non-embedding Copilot model catalog rather than discarding picker-disabled entries. It SHALL try `api.individual.githubcopilot.com` first, then `api.githubcopilot.com` if the first host fails or yields no non-embedding catalog entries. Requests SHALL include `Authorization`, `Copilot-Integration-Id: copilot-developer-cli`, and `X-GitHub-Api-Version: 2026-07-01`. The result SHALL retain the successful host and server model order. Alphabetical sorting SHALL apply only to the derived display list.

#### Scenario: Fetch complete catalog
- **WHEN** the individual endpoint returns picker-enabled, picker-disabled, and embedding models
- **THEN** the decoded catalog retains both picker-enabled and picker-disabled non-embedding models
- **AND** it excludes embedding models
- **AND** it records the individual endpoint as the catalog host

#### Scenario: Derive display models
- **WHEN** the catalog contains multiple chat-completions-compatible models
- **THEN** the explicit display list includes only models whose `model_picker_enabled` is not explicitly `false`
- **AND** the explicit display list is sorted alphabetically by name
- **AND** Auto hints preserve server order and include compatible picker-disabled models

#### Scenario: Dual endpoint fallback
- **WHEN** `api.individual.githubcopilot.com` returns a non-cancellation transport error, HTTP 404, HTTP 5xx, malformed successful model response, or no non-embedding catalog entries
- **THEN** the system retries catalog fetching against `api.githubcopilot.com`

#### Scenario: Capability-aware host fallback
- **WHEN** the individual host returns a decoded nonempty catalog but no model supporting `/chat/completions`
- **THEN** Auto translation fetches the business-host catalog before reporting no compatible models
- **WHEN** the individual host lacks the requested explicit compatible picker model
- **THEN** explicit-model validation fetches the business-host catalog before reporting the model unavailable

#### Scenario: Settings prefers selectable capability without losing Auto fallback
- **WHEN** the individual host has compatible Auto candidates but no compatible picker-enabled model
- **THEN** Settings retains the individual catalog as an Auto-only fallback and probes the business host
- **WHEN** business exposes compatible picker-enabled models
- **THEN** Settings uses the business catalog and displays the selectable state
- **WHEN** business is unsuitable or its probe fails
- **THEN** Settings uses the retained individual catalog and displays the Auto-only state
- **AND** a business probe failure is sanitized and logged without replacing the usable Settings state

#### Scenario: Catalogs are not merged across hosts
- **WHEN** the first suitable catalog is found
- **THEN** its host and model list are used together for selection and the following protocol transaction
- **AND** models from different hosts are not combined into one picker or hint list

#### Scenario: Catalog authorization and rate limits are terminal
- **WHEN** a catalog host returns HTTP 401, 403, or 429
- **THEN** the sanitized error is surfaced
- **AND** the alternate host is not attempted

#### Scenario: Optional Settings probe failure preserves retained Auto capability
- **WHEN** Settings has retained a compatible individual Auto-only catalog and its optional business probe returns an HTTP or transport failure
- **THEN** Settings uses the retained individual catalog
- **AND** the probe error is sanitized and logged rather than shown as the model-loading state

#### Scenario: Other catalog client errors are terminal
- **WHEN** a catalog host returns an HTTP 4xx response other than 401, 403, 404, or 429
- **THEN** the sanitized error is surfaced
- **AND** the alternate host is not attempted

#### Scenario: Both catalog endpoints fail
- **WHEN** both catalog hosts fail with fallback-eligible errors
- **THEN** model fetching throws the final typed or sanitized failure
- **AND** it does not return an empty array as a success value

### Requirement: Display model category in UI
The system SHALL display the model name followed by a human-readable category label in the selection UI. The label is derived from the `model_picker_category` field returned by the API.

#### Scenario: Displaying model name and category
- **WHEN** the user opens the model selection dropdown
- **THEN** each item shows the friendly name and category label, e.g.:
  - `"powerful"` → `"Claude Opus 4.5 (Premium)"`
  - `"versatile"` → `"Claude Sonnet 4.5 (Standard)"`
  - `"lightweight"` → `"GPT-5 mini (Lite)"`
  - no category → model name only

### Requirement: Copilot model selection persistence
The system SHALL persist the user's Copilot selection to `UserDefaults` under `copilotModel`. The virtual selection `auto` SHALL be the default when no preference exists. A resolved concrete Auto model SHALL remain ephemeral and SHALL NOT replace the persisted `auto` value. Explicit selections SHALL remain available only for compatible picker-enabled models exposed by the account.

#### Scenario: Default Copilot selection on first launch
- **WHEN** no `copilotModel` preference has been saved
- **THEN** the active Copilot selection is `auto`

#### Scenario: User selects Auto
- **WHEN** an account exposes explicit models and the user selects Auto
- **THEN** `auto` is persisted under `copilotModel`
- **AND** later Auto resolution does not overwrite that preference with a concrete model identifier

#### Scenario: User selects an explicit compatible model
- **WHEN** an account exposes a picker-enabled `/chat/completions` model and the user selects it
- **THEN** its identifier is persisted under `copilotModel`
- **AND** subsequent Copilot translations use that explicit model path

#### Scenario: Saved concrete model is unavailable on an Auto-only account
- **WHEN** the catalog has compatible Auto candidates but no compatible picker-enabled models
- **AND** the saved preference is a concrete model identifier
- **THEN** Settings normalizes the preference to `auto`

#### Scenario: Saved concrete model remains selectable
- **WHEN** the saved concrete model exists in the compatible picker-enabled display list
- **THEN** Settings preserves and displays that selection

#### Scenario: Failed or incompatible catalog does not destroy preference
- **WHEN** catalog loading fails or succeeds with no compatible model
- **THEN** the existing `copilotModel` preference remains unchanged

### Requirement: GitHub Copilot section in Settings UI
The API Keys tab in Settings SHALL include a GitHub Copilot section that displays Copilot CLI availability and the model capability state. An Auto-only account SHALL see an enabled model picker containing only `Auto`, without an additional explanatory caption. An account with compatible picker-enabled models SHALL see the same picker containing Auto followed by those models. The engine picker in Preferences SHALL show GitHub Copilot only when the CLI is installed, logged in, and the loaded catalog has at least one compatible model, or while catalog capability remains unknown due to idle/loading/failure state.

#### Scenario: GitHub Copilot section — Auto-only account
- **WHEN** the CLI is available and the loaded catalog has compatible Auto candidates but no compatible picker-enabled models
- **THEN** a green `Copilot CLI detected` label is shown
- **AND** Settings displays an enabled `Model` picker containing only `Auto`
- **AND** Settings does not display an additional Auto explanation

#### Scenario: GitHub Copilot section — selectable account
- **WHEN** the CLI is available and the loaded catalog has compatible picker-enabled models
- **THEN** a green `Copilot CLI detected` label is shown
- **AND** the model picker contains Auto followed by compatible picker-enabled models
- **AND** responses-only models are absent

#### Scenario: Retry model loading
- **WHEN** model loading is in the failed state and the user activates Retry
- **THEN** Settings transitions to loading and performs a new catalog request

#### Scenario: GitHub Copilot section — CLI not installed
- **WHEN** the Copilot CLI binary is not found
- **THEN** a label `GitHub Copilot CLI not found` is shown with installation instructions

#### Scenario: GitHub Copilot section — not logged in
- **WHEN** the CLI exists but no keychain token is present
- **THEN** a warning `Not logged in` is shown with instructions to run `copilot login`

#### Scenario: Engine picker hides Copilot when unavailable
- **WHEN** the CLI is not installed, the user is not logged in, or a successful catalog has no `/chat/completions`-compatible model
- **THEN** `GitHub Copilot` is absent from the translation-engine picker

#### Scenario: Model loading failure remains distinguishable from CLI failure
- **WHEN** the CLI is installed and logged in but model catalog loading fails
- **THEN** Settings continues to show `Copilot CLI detected`
- **AND** it displays the model-loading failure separately

### Requirement: Classify Copilot models by implemented transport
The system SHALL determine whether a Copilot model is usable by the current client from the model's `supported_endpoints` field. A model SHALL be considered chat-completions-compatible only when `supported_endpoints` contains the exact value `/chat/completions`. The system SHALL NOT infer endpoint compatibility from a model identifier, display name, family, picker category, `model_picker_enabled`, or policy field. A model with missing or empty `supported_endpoints` SHALL be incompatible.

#### Scenario: Model explicitly supports chat completions
- **WHEN** `/models` returns a non-embedding chat model whose `supported_endpoints` contains `/chat/completions`
- **THEN** the model is included in the chat-completions-compatible catalog

#### Scenario: Responses-only model is excluded
- **WHEN** `/models` returns a model whose `supported_endpoints` contains `/responses` but not `/chat/completions`
- **THEN** the model is excluded from Auto hints and the Settings model picker

#### Scenario: Picker-disabled model remains eligible for Auto
- **WHEN** a model supports `/chat/completions` and has `model_picker_enabled: false`
- **THEN** the model is eligible for Auto hints
- **AND** the model is not presented as an explicit picker option

#### Scenario: Missing endpoint metadata is not guessed
- **WHEN** a model omits `supported_endpoints`
- **THEN** the model is excluded from Auto hints and explicit selection

### Requirement: Explicit Copilot model loading states
The system SHALL represent Copilot model loading as distinct idle, loading, Auto-only, selectable, no-compatible-model, and failed states. Network, HTTP, and decoding failures SHALL result in the failed state and SHALL NOT be represented as an empty successful catalog.

#### Scenario: Catalog request is in progress
- **WHEN** Settings is waiting for the Copilot model catalog
- **THEN** the GitHub Copilot section displays `Checking models…` with progress indication

#### Scenario: Catalog request fails
- **WHEN** catalog loading terminates with a transport, HTTP, or decoding failure after applying the specified terminal-error and host-fallback rules
- **THEN** Settings displays `Couldn’t load Copilot models.`
- **AND** Settings provides a Retry button
- **AND** the saved Copilot model preference is unchanged

#### Scenario: No compatible model exists
- **WHEN** both hosts return successfully decoded catalogs containing no model supporting `/chat/completions`
- **THEN** Settings displays `No compatible Copilot models available.`
- **AND** GitHub Copilot is not offered by the translation-engine picker for that Settings lifetime
- **AND** the saved Copilot model preference is unchanged

### Requirement: Cache Copilot model catalogs safely
The system SHALL cache successful Copilot model catalogs in process memory for five minutes, keyed by host and authenticated-account token digest. Concurrent catalog requests for the same key SHALL share one in-flight fetch. A different account digest for the same host SHALL evict the previous account entry. Expired entries SHALL be removed before lookup. Raw OAuth tokens and token digests SHALL NOT be persisted, displayed, or logged. Catalog failures SHALL NOT be cached.

#### Scenario: Settings and translation share a fresh catalog
- **WHEN** Settings and translation request the same host and account catalog within five minutes
- **THEN** they receive the cached catalog
- **AND** only one `/models` request is required

#### Scenario: Concurrent catalog requests are single-flight
- **WHEN** multiple callers request the same uncached host and account catalog concurrently
- **THEN** exactly one `/models` request is issued
- **AND** all non-cancelled callers receive the same validated catalog

#### Scenario: Expired catalog is fetched again
- **WHEN** a cached catalog is five minutes old or older
- **THEN** it is removed before lookup
- **AND** the next caller performs a new `/models` request

#### Scenario: Catalog error is not cached
- **WHEN** a catalog request fails
- **THEN** the failure is surfaced
- **AND** the next retry performs a new request

#### Scenario: Model protocol drift invalidates the catalog
- **WHEN** inference returns `model_not_supported` or `unsupported_api_for_model`, or model-session selection violates the compatible hint set
- **THEN** the matching host and account catalog entry is invalidated before bounded recovery
