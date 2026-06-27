## 1. Baseline and TDD Guardrails

- [x] 1.1 Run the existing focused suites with `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' -only-testing MangaTranslatorTests/CopilotEnvironmentTests -only-testing MangaTranslatorTests/CopilotTranslationServiceTests -only-testing MangaTranslatorTests/PreferencesServiceTests`; record any pre-existing failure before editing production code.
- [x] 1.2 For every numbered behavior slice below, execute exactly one RED test addition, run its narrow suite and confirm the failure is caused by missing requested behavior, implement only the corresponding GREEN change, then rerun that suite plus all earlier slices before starting the next RED test.
- [x] 1.3 Do not refactor while any new or existing focused test is red; after a GREEN step, keep refactoring behavior-neutral and rerun the same focused suites immediately.

## 2. Model Metadata and Compatibility Classification

- [x] 2.1 RED — add one `CopilotEnvironmentTests` behavior test proving a model decodes `supported_endpoints`, `model_picker_enabled`, and `capabilities.type`; include a model with missing optional metadata and confirm decoding still succeeds. Run the suite and observe the intended failure.
- [x] 2.2 GREEN — minimally extend `CopilotModel` and `CopilotEnvironment.parseModels` to retain `pickerEnabled`, `supportedEndpoints`, and `capabilityType` while preserving ID, display name, category, and embedding exclusion; run the suite to green.
- [x] 2.3 RED — add one behavior test proving exact endpoint classification: `/chat/completions` is compatible, `/responses`-only and missing-endpoint models are incompatible. Run and observe failure.
- [x] 2.4 GREEN — add the smallest public/computed compatibility behavior needed to pass; compare the exact `/chat/completions` string and do not infer by model name or family. Run all slice-2 tests.
- [x] 2.5 RED — add one behavior test proving a picker-disabled compatible model remains in Auto hints while being absent from explicit selectable models, and that Auto hint order matches server order while explicit display order is alphabetical. Run and observe failure.
- [x] 2.6 GREEN — introduce the minimal catalog/derived-list interface that exposes `autoHintModelIDs` and `selectableModels` with those semantics. Run all slice-2 tests.
- [x] 2.7 REFACTOR — consolidate duplicate catalog filtering/sorting behind the catalog interface without changing observable arrays; rerun `CopilotEnvironmentTests`.

## 3. Catalog Fetch Contract and Host Fallback

- [x] 3.1 RED — replace or update the existing header test to assert `/models` receives `Authorization`, `Copilot-Integration-Id: copilot-developer-cli`, and `X-GitHub-Api-Version: 2026-07-01`, and that the result records the successful individual host. Run and observe failure.
- [x] 3.2 GREEN — add one Copilot API-version constant and return a catalog result containing its host; preserve `.shared` as the production URLSession default. Run the test to green.
- [x] 3.3 RED — add one behavior test proving a successful individual-host catalog retains picker-disabled non-embedding models instead of falling back merely because the explicit picker list is empty. Run and observe failure.
- [x] 3.4 GREEN — change catalog success criteria to decoded non-embedding catalog entries rather than picker-visible entries. Run all slice-3 tests.
- [x] 3.5 CHARACTERIZATION — add one parameterized behavior test covering fallback-eligible individual-host failures only: non-cancellation transport error, HTTP 404, HTTP 5xx, malformed HTTP-200 JSON, and an HTTP-200 catalog with no non-embedding entry. Each case must issue exactly one business-host `/models` request. The existing implementation already satisfied these cases, so record them as characterization coverage rather than manufacturing a RED failure.
- [x] 3.6 GREEN — implement bounded individual-to-business catalog fallback for only those cases. Preserve cancellation without fallback. Run all slice-3 tests.
- [x] 3.7 RED — add one parameterized terminal-error test for HTTP 400, 401, 403, and 429; assert the sanitized error is surfaced and no business-host request occurs. Run and observe failure.
- [x] 3.8 GREEN — classify authorization, rate limits, and non-404 client errors as terminal. Run all slice-3 tests.
- [x] 3.9 RED — add one behavior test proving fallback-eligible failure of both hosts throws the final typed or sanitized failure and is distinguishable from a successful empty compatible set. Run and observe failure.
- [x] 3.10 GREEN — remove empty-array-as-error behavior from the catalog API and propagate the final failure. Run `CopilotEnvironmentTests` and all earlier focused suites.
- [x] 3.10a RED — add capability-aware host-selection tests proving: Auto translation selects the first chat-compatible host; explicit translation searches for the requested compatible picker model; Settings prefers selectable capability but retains an individual Auto-only catalog if the business probe is unsuitable or fails. Assert catalogs are never merged. Run and observe failure.
- [x] 3.10b GREEN — separate host-specific catalog fetching from the three operation-specific selection policies and return one host/catalog pair. Report no-compatible/model-unavailable only after each policy's exact search is exhausted. Run host-selection tests.
- [x] 3.11 RED — with an injected clock and isolated catalog store, add one test proving Settings and translation reuse the same host/account catalog before five minutes, while a catalog exactly five minutes old is refetched. Run and observe failure.
- [x] 3.12 GREEN — add a process-local `CopilotModelCatalogStore` actor keyed by host and OAuth-token SHA256 digest with an exact five-minute TTL; inject isolated stores in tests. Run catalog tests.
- [x] 3.13 RED — add one concurrency/account-isolation behavior test proving concurrent same-key requests issue one `/models` call, failures are not cached, and observing a new account digest for the same host evicts the previous entry. Run and observe failure.
- [x] 3.14 GREEN — implement catalog single-flight, failed-task removal, expired-entry pruning, and same-host account replacement. Do not persist or log OAuth tokens/digests. Run catalog tests repeatedly.
- [x] 3.15 REFACTOR — centralize Copilot request headers, host constants, clock injection, and cache-key construction inside the Copilot boundary without changing OpenAI headers; rerun focused suites.

## 4. Preference Default and Capability State

- [x] 4.1 RED — add one `PreferencesServiceTests` test asserting a fresh store defaults `copilotModel` to `auto`. Run and observe the existing `gpt-5-mini` failure.
- [x] 4.2 GREEN — change only `defaultCopilotModel` to `auto`; run `PreferencesServiceTests` to green.
- [x] 4.3 RED — add one model-state behavior test proving a compatible catalog with no compatible picker-enabled models becomes `.autoOnly`, while a catalog with compatible picker models becomes `.selectable` containing Auto first. Run and observe failure.
- [x] 4.4 GREEN — introduce `CopilotModelLoadState` and minimal deterministic state derivation from the catalog. Run the new state test.
- [x] 4.5 RED — add one behavior test proving no compatible model becomes `.noCompatibleModels`, while a catalog fetch error becomes `.failed` rather than the same empty state. Run and observe failure.
- [x] 4.6 GREEN — implement the two distinct transitions and retain a safe user-facing error category/message without provider payloads. Run all slice-4 tests.
- [x] 4.7 RED — add one preference-normalization test for each outcome in a single parameterized behavior set: Auto-only normalizes an unavailable concrete value to `auto`; selectable preserves a valid concrete value; selectable normalizes an absent value to `auto`; failed and no-compatible states preserve the stored value. Run and observe failure.
- [x] 4.8 GREEN — implement normalization as a deterministic helper invoked only after successful catalog classification. Run `PreferencesServiceTests` and model-state tests.

## 5. Settings User Experience

- [x] 5.1 RED — add one Settings behavior/source-correctness test proving `.autoOnly` renders a noninteractive `Model` value `Auto` plus `GitHub selects a compatible model automatically.`, and does not render a disabled one-item Picker. Run and observe failure.
- [x] 5.2 GREEN — update `SettingsView` to render the Auto-only state exactly as specified while preserving the existing green CLI-detected label. Run the Settings-focused test.
- [x] 5.3 CHARACTERIZATION — add one Settings behavior test proving `.selectable` renders a Picker with Auto first and only compatible picker-enabled concrete models. The implementation introduced by 5.2 already satisfied this behavior, so record it as characterization coverage rather than manufacturing a RED failure.
- [x] 5.4 GREEN — connect the selectable state to the existing preference binding and labels; do not expose responses-only models. Run all Settings slice tests.
- [x] 5.5 RED — add one behavior test proving loading, no-compatible-model, and failed states render distinct strings; failed renders a Retry action that transitions to loading and performs another fetch. Run and observe failure.
- [x] 5.6 GREEN — replace the current `try?`/empty-array path with explicit asynchronous state transitions and a retryable load action. Run all Settings slice tests.
- [x] 5.7 RED — add one engine-availability behavior test proving Copilot is hidden for missing CLI, missing login, and successful no-compatible state, while a catalog request failure remains visually distinct from CLI failure and does not erase the preference. Run and observe failure.
- [x] 5.8 GREEN — derive engine visibility from CLI availability plus known compatible-catalog state without treating catalog failure as logout. Run Settings and Preferences suites.
- [x] 5.9 REFACTOR — extract deterministic catalog-to-`CopilotModelLoadState` derivation from `SettingsView`, keep all I/O in `.task`/button actions and out of `body`, and rerun SwiftUI correctness tests.
- [x] 5.10 RED — update the Auto-only Settings behavior test to require the same enabled Picker used by selectable accounts, containing only Auto and no explanatory caption; run and observe the fixed-value implementation fail.
- [x] 5.11 GREEN — centralize loaded-state picker rendering, pass `[.auto]` for Auto-only accounts, remove the redundant caption, and rerun Settings and Preferences suites.

## 6. Auto Session Tracer Bullet

- [x] 6.1 RED — add one end-to-end `CopilotTranslationServiceTests` tracer test through the public token-injected `translate` entry point. Mock `/models`, `/models/session`, and `/chat/completions`; assert the session request omits a responses-only model from `model_hints`, inference body uses returned `gpt-5-mini` rather than `auto`, inference carries `Copilot-Session-Token`, integration ID, and API version, and parsed translated bubbles are returned. Run and observe failure before any resolver implementation.
- [x] 6.2 GREEN — implement the smallest `CopilotAutoSessionResolver` and Auto branch in `CopilotTranslationService` needed to pass the tracer test; reuse existing prompt and response parsing and keep `ChatCompletionsClient` provider-neutral. Run the tracer plus all prior focused suites.
- [x] 6.3 RED — add the equivalent public `translateBatch` tracer test proving one compatibility-filtered model session is resolved and the existing multi-page response is parsed in requested order. Run and observe failure.
- [x] 6.4 GREEN — route batch translation through the same resolved concrete client/session without duplicating handshake logic. Run single-page and batch tracer tests.
- [x] 6.5 REFACTOR — create one host-local operation that owns catalog → session → concrete client construction for both translation methods; rerun `CopilotTranslationServiceTests`.

## 7. Auto Session Validation Boundaries

- [x] 7.1 RED — add one parameterized resolver behavior test for missing `selected_model`, missing/empty `session_token`, present-invalid/nonfuture `expires_at`, selected model absent from `available_models`, and selected model outside the submitted compatible hint set. Each case must assert no inference request. Run and observe failure.
- [x] 7.2 GREEN — add strict model-session decoding and invariant validation sufficient for those cases; expose one typed protocol failure without response-body leakage. Run resolver/service tests.
- [x] 7.2a CHARACTERIZATION — add one public translation test proving an otherwise valid response without `expires_at` supports its immediate inference but is not reused by the next translation. The minimal resolver introduced by 6.2 already had optional expiry and no cache, so record this as characterization coverage rather than manufacturing a RED failure.
- [x] 7.2b GREEN — make expiry optional in the resolved-session value, return expiry-less sessions without inserting them into cache, and reacquire on the next translation. Run resolver/service tests.
- [x] 7.3 CHARACTERIZATION — add one test proving an empty compatible hint set fails before `/models/session` and `/chat/completions` and yields the no-compatible-model error. Capability-aware catalog selection already enforced this precondition, so record it as characterization coverage rather than manufacturing a RED failure.
- [x] 7.4 GREEN — add the precondition at the service boundary. Run all slice-7 tests.
- [x] 7.5 RED — add one test proving cancellation before or during catalog/session acquisition propagates and issues no later session, inference, retry, or business-host request. Run and observe failure.
- [x] 7.6 GREEN — preserve `CancellationError` and `URLError.cancelled` through the resolver and host transaction. Run all Copilot service tests.

## 8. Session Cache, Expiry, and Concurrency

- [x] 8.1 RED — with an injected clock and isolated resolver, add one behavior test proving a session expiring more than five minutes later is reused by a subsequent public translation without a second `/models/session` request. Run and observe failure.
- [x] 8.2 GREEN — add the minimal memory-only cache keyed by host, OAuth-token SHA256 digest, and ordered hint sequence. Do not persist or log any key/token. Run the test to green.
- [x] 8.3 RED — add one injected-clock boundary test proving a session with 301 seconds remaining is reused, a session with exactly 300 seconds remaining is refreshed with the old `Copilot-Session-Token` and identical ordered hints, and an expired session is acquired without any old session header. Run and observe failure.
- [x] 8.4 GREEN — implement the exact three-state reuse/refresh/acquire state machine. Run all cache tests.
- [x] 8.5 RED — add tests proving: a valid refresh with future expiry may return a different compatible `selected_model` and atomically replaces model/token/expiry; an otherwise valid refresh without expiry removes the old cache entry, supports immediate inference, and forces acquisition next time. Run and observe failure.
- [x] 8.6 GREEN — validate refresh with the same invariants as acquisition, atomically replace expiring sessions, and keep expiry-less results immediate-use-only. Run cache and tracer tests.
- [x] 8.7 RED — add one test where refresh returns HTTP 401, followed by successful headerless acquisition; assert exactly one request carries the old token and the acquisition/inference do not. Add a second case where acquisition returns 401/403 and no inference or host fallback follows. Run and observe failure.
- [x] 8.8 GREEN — implement one headerless acquisition fallback after refresh 401 and terminal OAuth classification after acquisition 401/403. Run all refresh tests.
- [x] 8.9 RED — add one injected-clock test proving refresh transport/5xx failure reuses the old session only if it remains strictly unexpired after failure; when expiry passes during failure, assert no inference uses it and normal host fallback begins. Run and observe failure.
- [x] 8.10 GREEN — recheck the clock after transient refresh failure and conditionally return the old session without mutating it. Run refresh and host tests.
- [x] 8.11 RED — add one parameterized test proving refresh cancellation, HTTP 429, HTTP 403/other non-404 4xx, malformed success, and invariant-invalid success never reuse the old token; cancellation is immediate, 429 is terminal, and only fallback-eligible failures may proceed to another host. Run and observe failure.
- [x] 8.12 GREEN — implement exact refresh error classification without matching arbitrary message prose. Run all refresh tests.
- [x] 8.13 RED — add one concurrency behavior test proving concurrent callers share exactly one acquisition or refresh; cancelling one waiting caller does not cancel shared work or fail other callers. Run and observe failure.
- [x] 8.14 GREEN — add actor-owned single-flight tasks, caller-local cancellation handling, and failed-task cleanup. Run concurrency tests repeatedly.
- [x] 8.15 RED — add one test proving a different host cannot receive the old session token; a new OAuth digest for the same host evicts all old-account sessions/in-flight work; a new hint sequence for the same host/account evicts the superseded session; expired entries are pruned; and invalidation during an in-flight refresh prevents its completion from repopulating cache. Run and observe failure.
- [x] 8.16 GREEN — complete cache-key isolation, superseded-entry eviction, lazy expiry pruning, and generation-based invalidation. Run slice-8 tests under Thread Sanitizer if supported; otherwise run concurrency cases at least ten times.
- [x] 8.17 REFACTOR — deepen resolver internals behind one resolve/invalidate interface; rerun all Copilot tests.

## 9. Explicit Model Path

- [x] 9.1 RED — add one public translation test proving a saved concrete model that is picker-enabled and `/chat/completions`-compatible is sent directly without `/models/session` or `Copilot-Session-Token`. Run and observe failure.
- [x] 9.2 GREEN — implement catalog validation plus the existing direct concrete client path. Run the test and existing direct-model error tests.
- [x] 9.3 CHARACTERIZATION — add one parameterized test proving an absent, picker-disabled, responses-only, or missing-endpoint explicit model fails actionably before inference and is never silently replaced with Auto. Catalog validation added by 9.2 already enforced this behavior, so record it without manufacturing a RED failure.
- [x] 9.4 GREEN — implement the explicit-model unavailable error only after capability-aware individual-to-business host selection is exhausted, and keep preference normalization in Settings rather than mutating preferences from the translation service. Run all slice-9 tests.
- [x] 9.5 RED — add one explicit-path host-transaction test where individual inference exhausts a fallback-eligible failure and business succeeds; assert business refetches/validates its catalog, sends the explicit model without any Auto session token, and preserves existing parsing. Run and observe failure.
- [x] 9.6 GREEN — wrap explicit catalog validation plus inference in the same bounded host fallback used by Copilot routing, omitting all Auto-session behavior. Run all explicit and fallback tests.

## 10. Recovery, Error Policy, and Host Isolation

- [x] 10.1 RED — add one request-sequence test where Auto inference first returns `model_not_supported`, invalidation produces a new session/model, and the recovery inference succeeds; assert the stale model/session inference occurs exactly once, exactly two model-session acquisitions occur, and there is no third resolution. Run and observe failure against the current all-errors retry loop.
- [x] 10.2 GREEN — add an injectable API-error retry classifier to `ChatCompletionsClient` with current behavior as the default; configure Copilot so only transport/5xx API failures retry internally, then implement one bounded catalog/session invalidation and recovery outside the parser retry loop. Keep parse retries unchanged. Run the test to green and verify OpenAI tests are unchanged.
- [x] 10.3 CHARACTERIZATION — add one repeated-error test for both `model_not_supported` and `unsupported_api_for_model`; assert the second sanitized error is surfaced and acquisition remains capped at two. The bounded recovery introduced by 10.2 already satisfied the repeated-error behavior.
- [x] 10.4 GREEN — complete code-based recovery classification without matching arbitrary message prose. Run recovery tests.
- [x] 10.5 RED — add one Auto inference-401 test proving the session is invalidated and exactly one headerless acquisition occurs; cover successful acquisition plus recovery inference, and acquisition 401/403 with no inference or host fallback. Run and observe failure.
- [x] 10.6 GREEN — implement inference-401 session recovery and terminal OAuth classification. Explicit-model 401 remains terminal without session recovery. Run recovery tests.
- [x] 10.7 CHARACTERIZATION — add one mixed-error sequence test proving all Auto recovery causes share one per-translation budget: after any recovery inference, a different recoverable error is surfaced without another catalog fetch, session acquisition, or inference. The single recovery boundary introduced by 10.2 already enforced the shared budget.
- [x] 10.8 GREEN — add one recovery-budget value owned by the host-local translation operation rather than separate counters per error type. Run all recovery tests.
- [x] 10.9 RED — add one host-isolation test where fallback-eligible individual catalog/session protocol failure is followed by business success; assert the business transaction fetches its own catalog/session and never receives the individual session token. Run and observe failure.
- [x] 10.10 GREEN — move endpoint fallback around the entire host-local protocol transaction. Preserve existing individual-first order. Run all fallback tests and update obsolete request-count assertions deliberately.
- [x] 10.11 CHARACTERIZATION — add separate behavior tests proving OAuth 401/403, HTTP 429, and other nonrecoverable 4xx errors are sent once and do not trigger chat-client retry, business-host fallback, refresh, session reacquisition, or arbitrary concrete-model selection. The retry classifier and host transaction already satisfied these terminal cases.
- [x] 10.12 GREEN — classify terminal errors consistently across chat-client retry, catalog, refresh, acquisition, and inference while retaining sanitized provider errors. Run error and fallback tests.
- [x] 10.13 CHARACTERIZATION — existing focused tests prove ordinary inference 5xx and parse failures still use the two-attempt `ChatCompletionsClient` behavior and batch fallback semantics; rerun them after the retry-classifier change.
- [x] 10.14 GREEN — make only compatibility adjustments needed to preserve the existing retry/parser contract. Run the complete `CopilotTranslationServiceTests` suite.

## 11. Security and Diagnostic Logging

- [x] 11.1 RED — add one `DebugLoggerAPIErrorTests` or focused Copilot diagnostic test proving successful Auto resolution records only resolved model ID and sanitized endpoint, with no OAuth token, session token, token digest, request body, or response body. Run and observe failure.
- [x] 11.2 GREEN — add one operational routing diagnostic through existing `DebugLogger` APIs using allowlisted metadata only. Run the diagnostic test.
- [x] 11.3 RED — add one model-session error test containing bearer tokens, email, query secrets, and long opaque strings; assert UI-facing and persisted descriptions contain none of them and remain within the existing message bound. Run and observe failure if the new path bypasses sanitization.
- [x] 11.4 GREEN — route model-session non-2xx errors through `APIErrorSanitizer` and existing structured logging without retaining raw bodies. Run sanitizer and debug-log suites.
- [x] 11.5 REFACTOR — audit all new log calls and error associated values for credentials; remove any raw payload storage and rerun security tests.

## 12. Final Verification and Manual Functional Test

- [x] 12.1 Run focused suites: `CopilotEnvironmentTests`, `CopilotTranslationServiceTests`, `PreferencesServiceTests`, `APIErrorSanitizerTests`, `DebugLoggerAPIErrorTests`, and relevant Settings/SwiftUI correctness tests; confirm zero failures and zero skipped tests.
- [x] 12.2 Run the full main suite with `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS'`; report any failure exactly and do not claim success if tests are skipped or unavailable.
- [x] 12.3 Run `xcodebuild -project MangaTranslator.xcodeproj -scheme MangaTranslator -configuration Debug build` and confirm no new Swift concurrency or deprecation warnings originate from changed files.
- [x] 12.4 On a logged-in Copilot Student account, open Settings and confirm the enabled Model picker contains only Auto, has no additional explanatory caption, and the GitHub Copilot engine remains visible.
- [x] 12.5 Translate one page and one multi-page batch; confirm both complete, later requests reuse a session with more than five minutes remaining, a nearly expired session refreshes on the same host using its old session header, an expired session acquires without the old header, responses-only models are never sent to `/chat/completions`, and cancellation still stops without retry.
- [x] 12.6 Inspect persistent debug logs and exported diagnostics; confirm the resolved concrete model is diagnosable and no OAuth token, Copilot session token, token digest, prompt/request body, or model-session response body is present.
- [x] 12.7 Re-run `openspec status --change support-copilot-auto-model-routing` and `openspec validate support-copilot-auto-model-routing` (or the installed CLI's equivalent validation command); resolve every artifact/spec validation error before implementation is considered complete.
