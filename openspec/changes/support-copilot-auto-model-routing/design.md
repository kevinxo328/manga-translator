## Context

GitHub Copilot's `auto` value is a virtual client-side selection, not a model identifier accepted by `/chat/completions`. The verified protocol first calls `POST /models/session`, receives `selected_model`, `available_models`, `session_token`, and `expires_at`, then sends the concrete model and `Copilot-Session-Token` on inference. A live Student account accepted this sequence and completed a `gpt-5-mini` chat-completions request. Sending `model: "auto"` directly returned `model_not_supported`.

The `/models` response is also the only verified source for transport compatibility. For example, `gpt-5-mini` advertises `/chat/completions`, while `gpt-5.3-codex` and `gpt-5.4-mini` can advertise only `/responses`. A session requested with the unconstrained `auto` hint may select a responses-only model, which MangaTranslator cannot currently call. `model_picker_enabled` is not a transport or entitlement signal: Student Auto models can be picker-disabled and still be valid Auto candidates.

The current implementation loses these distinctions:

- `CopilotModel` stores only `id`, display name, and picker category.
- `CopilotEnvironment.fetchModels` removes picker-disabled models and converts fetch failure into an empty result at the Settings call site.
- `PreferencesService` defaults to `gpt-5-mini`.
- `CopilotTranslationService` passes the stored string directly to `ChatCompletionsClient`.
- `ChatCompletionsClient` always calls `/chat/completions` and has no Copilot session-token concept.
- `TranslationViewModel.translationService` creates one service per translation operation. A batch keeps that instance for the operation, but separate single-page operations create separate instances.

The relevant GitHub endpoints are private Copilot protocol rather than a public stable REST API. The installed official Copilot CLI 1.0.65 SDK declares `AutoModeSessionResult.expiresAt` as optional even though the observed live response supplied it. A live same-host refresh using the old `Copilot-Session-Token` returned HTTP success, the same selected model and expiry, and a rotated session token; therefore refresh must atomically replace the token even when model and expiry do not change. The integration needs one narrow boundary, explicit validation, deterministic behavior for expiry-less sessions, sanitized logging, and tests that make protocol drift visible.

## Goals / Non-Goals

**Goals:**

- Make Copilot Auto work for Free and Student accounts without sending `model: "auto"` to inference.
- Derive `/chat/completions` compatibility exclusively from `supported_endpoints` returned by `/models`.
- Preserve explicit model selection for accounts that expose compatible picker-enabled models.
- Give Settings distinct loading, ready, empty-compatible-set, and failure presentations.
- Keep OAuth and session tokens out of UserDefaults, persistent logs, errors, and UI.
- Reuse a valid session across concurrent page calls and batch calls, and deduplicate concurrent acquisition.
- Bound all refresh and recovery paths so a single translation cannot loop indefinitely.
- Keep the existing prompt construction, JSON response parsing, retry budget, endpoint ordering, and cancellation behavior.
- Implement through vertical TDD slices using observable requests, responses, preference state, and UI state.

**Non-Goals:**

- Implement `/responses`, WebSocket responses, or Anthropic `/v1/messages` in this change.
- Call `/models/session/intent` or reproduce task-complexity routing performed by full Copilot clients.
- Let Auto select a model that does not support `/chat/completions`.
- Persist the resolved concrete Auto model or short-lived session token.
- Expose the resolved concrete model as a user-selectable or durable Settings value.
- Change translation cache keys, prompts, response parsing, rate-limit policy, or non-Copilot providers.
- Guarantee compatibility with future undocumented Copilot protocol changes without a code update.

## Decisions

### D1. Preserve the full model catalog and derive separate views

`CopilotModel` will gain the decoded fields needed for decisions:

```swift
struct CopilotModel: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String?
    let pickerEnabled: Bool?
    let supportedEndpoints: Set<String>
    let capabilityType: String?
}
```

The catalog preserves server order for protocol hints. Presentation code alphabetically sorts only the derived picker list. The following derived sets have different meanings and MUST remain separate:

- `chatCompletionModels`: non-embedding chat models whose `supportedEndpoints` contains the exact string `/chat/completions`, regardless of picker visibility or `policy`.
- `selectableModels`: `chatCompletionModels` whose `pickerEnabled` is not explicitly `false`, sorted by display name.
- `autoHintModelIDs`: IDs of `chatCompletionModels` in server order.

Models with missing `supported_endpoints` are incompatible, not "probably compatible". Models are not filtered by `policy.state`; `/models/session` remains the entitlement authority.

Alternative rejected: infer transport from model families or names. GitHub changes model inventory independently of the app and the live response already demonstrates mixed transports.

Alternative rejected: continue returning only picker models. That makes every Auto-only Student account appear to have no usable models.

### D2. Fetching returns a catalog or an explicit failure

`CopilotEnvironment` will expose a host-specific catalog fetch plus a capability-aware host selector that tries hosts in this order:

1. `https://api.individual.githubcopilot.com`
2. `https://api.githubcopilot.com`

Each host fetch calls `/models` with OAuth authorization, `Copilot-Integration-Id: copilot-developer-cli`, and the Copilot API version constant. A decoded catalog requires HTTP 200, a decodable `data` array, and at least one decoded non-embedding model. Protocol-error host fallback is allowed only for a non-cancellation transport failure, HTTP 404, HTTP 5xx, malformed successful response, or an empty successful catalog. HTTP 401, 403, 429, and every other 4xx response are terminal and do not try the second host. After both fallback-eligible host attempts fail, the operation throws the last sanitized/typed failure; it never returns an empty array as a substitute for failure.

A decoded nonempty catalog can still be unsuitable for the requested operation. The capability-aware selector uses these exact policies without merging catalogs:

- Auto translation: choose the first host with at least one `/chat/completions`-compatible model; continue to business only when individual has none.
- Explicit translation: choose the first host exposing the requested model as picker-enabled and `/chat/completions`-compatible; continue when individual does not.
- Settings: prefer the first host with at least one compatible picker-enabled model. If individual has compatible Auto candidates but no selectable models, retain it as an Auto-only fallback candidate and probe business. Use business if it has selectable models; otherwise use the retained individual Auto-only catalog. Any business probe failure is sanitized and logged but does not replace a usable retained individual Auto-only catalog with an error.

If neither host supplies even an Auto-compatible Settings catalog, Settings reports `.noCompatibleModels`; if neither supplies an explicit requested model, translation reports the model-unavailable error. Unsuitability is not logged or surfaced as an HTTP failure. Catalogs remain host-specific and are never merged; the selected host owns the following session/inference transaction.

The host that returned a catalog is part of the result. Auto session acquisition and the inference using that session remain on that same host. A session token is never moved between hosts.

A process-local `CopilotModelCatalogStore` actor caches a successful host-specific catalog for five minutes. Its key is `(host, SHA256(OAuth token))`; it never stores the raw OAuth token as a key. Concurrent requests for one key share one in-flight fetch. A different OAuth digest for the same host evicts the previous account's entry. Expired entries are removed lazily before lookup. Settings and translation use the same injected production store, while tests use isolated stores and an injected clock. Retry from the Settings failure state bypasses no valid cache because failures are never cached. `model_not_supported`, `unsupported_api_for_model`, and a model-session selection outside the compatible hint set invalidate the matching catalog entry before recovery.

### D3. Settings classifies account capability without acquiring an Auto session

Settings fetches only `/models`. It does not call `/models/session`, because opening Settings must not mint a short-lived session that may expire before translation.

The UI uses this state machine:

```swift
enum CopilotModelLoadState: Equatable {
    case idle
    case loading
    case autoOnly
    case selectable([CopilotModel])
    case noCompatibleModels
    case failed(String)
}
```

State derivation after a successful catalog fetch is exact:

- no `chatCompletionModels` -> `.noCompatibleModels`
- at least one compatible model and no `selectableModels` -> `.autoOnly`
- at least one `selectableModels` -> `.selectable([.auto] + selectableModels)`

The UI presentation is:

- `.loading`: `ProgressView("Checking models…")`
- `.autoOnly`: noninteractive labeled value `Model` / `Auto`, plus `GitHub selects a compatible model automatically.`
- `.selectable`: Picker containing `Auto` followed by compatible picker-enabled models
- `.noCompatibleModels`: after both hosts return no suitable chat-completions catalog, error text `No compatible Copilot models available.`; Copilot is not selectable as the translation engine for this Settings lifetime
- `.failed`: error text `Couldn’t load Copilot models.` and a `Retry` button; Copilot availability is not rewritten as not-installed or not-logged-in

CLI-not-installed and not-logged-in presentations remain unchanged. All code and UI strings remain English.

Alternative rejected: display a disabled Picker containing only Auto. A disabled control implies unavailable interaction rather than an intentional account capability.

Alternative rejected: show `Auto → <resolved model>` persistently. Resolution occurs at translation time and can change after refresh, making the Settings label stale.

### D4. `auto` is the persisted virtual selection; the concrete result is ephemeral

The first-launch default becomes `auto`. `CopilotModel.auto` is reintroduced only as a UI/preference value; it is never serialized into an inference request.

After a successful Settings catalog fetch:

- `.autoOnly` forces an unavailable saved concrete preference to `auto`.
- `.selectable` preserves a saved concrete selection only if its ID exists in the selectable list; otherwise it normalizes to `auto`.
- `.noCompatibleModels` and `.failed` do not overwrite the saved preference.
- An unavailable CLI does not overwrite the saved model preference.

This is a reversible migration because the legacy value remains valid when it reappears in a future selectable catalog; no destructive UserDefaults migration marker is added.

### D5. Auto session resolution is an actor with single-flight acquisition and refresh

Add a focused `CopilotAutoSessionResolver` actor. Its public operation accepts the OAuth token, host, and ordered compatible model IDs and returns:

```swift
struct CopilotResolvedSession: Sendable {
    let modelID: String
    let sessionToken: String
    let expiresAt: Date?
}
```

Initial acquisition calls `POST <host>/models/session` using:

- `Authorization: Bearer <OAuth token>`
- `Content-Type: application/json`
- `Copilot-Integration-Id: copilot-developer-cli`
- `X-GitHub-Api-Version: 2026-07-01`
- body `{ "auto_mode": { "model_hints": [<compatible IDs>] } }`
- no `Copilot-Session-Token` header

The response must contain nonempty `selected_model` and `session_token`, and `available_models` containing `selected_model`. The selected model must also be in the supplied compatible-ID set. When `expires_at` is present it must decode as a Unix timestamp strictly later than the validation clock. A response without `expires_at` is valid only as a noncacheable session for the immediate inference; the next translation acquires again. A present but invalid or nonfuture expiry is a protocol error. Failure of any invariant is a protocol error and no inference request is sent.

The resolver cache key is `(host, SHA256(OAuth token), compatible model ID sequence)`. The raw OAuth token is not stored as a key, logged, or persisted. Observing a new OAuth digest for a host evicts all prior session entries and invalidates in-flight work for that host. Observing a new compatible hint sequence for the same host/account evicts the prior hint-key session. Expired entries are removed lazily before lookup, so session credentials from old accounts or catalogs do not remain reachable until process exit. Resolution uses the following exact expiry state machine, evaluated with an injected clock:

1. `expiresAt - now > 300 seconds`: return the cached session unchanged.
2. `0 < expiresAt - now <= 300 seconds`: refresh before inference by calling the same `POST <host>/models/session` request with the same body and an additional `Copilot-Session-Token: <old session token>` header.
3. `expiresAt - now <= 0`: discard the expired session and perform initial acquisition without a `Copilot-Session-Token` header.

A successful refresh is validated by the same invariants as acquisition and atomically replaces the model, session token, and expiry; the concrete model is allowed to change. If a successful refresh omits expiry, the replacement is returned for immediate inference but no session remains cached. Refresh never sends the old token to a different host, account key, or hint-set key.

Refresh failure handling is bounded and deterministic:

- cancellation propagates immediately;
- HTTP 401 from refresh discards the old session and performs exactly one initial acquisition without the old token; if that acquisition returns 401/403, the OAuth failure is terminal;
- HTTP 429 is terminal and does not reuse the old token or change host;
- a non-cancellation transport failure or HTTP 5xx reuses the old session only if it is still unexpired at the post-failure clock check; otherwise the host transaction fails and normal host fallback rules apply;
- HTTP 403, 404, any other 4xx, malformed success data, or an invariant-invalid refresh response does not reuse the old session and proceeds through normal terminal/fallback classification.

Concurrent callers for the same key share one in-flight acquisition or refresh task. Cancellation of one waiting caller stops that caller's wait but does not cancel shared work required by other callers. Failed in-flight tasks are removed. Invalidation increments a per-key generation; completion from an older generation cannot repopulate the cache after invalidation.

The default resolver is process-local and injected into `CopilotTranslationService`; tests receive an isolated resolver. This allows separate single-page operations to reuse sessions while keeping tests deterministic.

Alternative rejected: cache only inside each `CopilotTranslationService`. The view model recreates the service for separate operations, causing unnecessary session acquisition.

Alternative rejected: persist the session token. It is a credential with a short expiry and has no valid cross-launch use.

### D6. Auto inference uses the concrete model and session header

When the preference is `auto`, `CopilotTranslationService` performs this sequence per host:

1. Fetch or reuse the model catalog for that host through the five-minute catalog store.
2. Derive nonempty `autoHintModelIDs` from exact `/chat/completions` support.
3. Resolve/reuse an Auto session from the resolver.
4. Create `ChatCompletionsClient` with `model` equal to the resolved concrete model.
5. Add `Copilot-Session-Token: <session token>`, `Copilot-Integration-Id`, and the Copilot API version to the inference request.
6. Run the existing single-page or batch prompt, retry, parse, and fallback behavior.

When the preference is a concrete model, the service validates that it is a picker-enabled `/chat/completions` model from the fetched catalog, then uses the existing direct inference path without a `Copilot-Session-Token`. It must never silently replace an explicit valid choice with Auto. If the saved choice is unavailable, translation fails with a typed actionable error; Settings normalization handles the normal migration path.

The shared `ChatCompletionsClient` remains provider-neutral. It accepts extra headers as it does now; Copilot owns session resolution and supplies the concrete model and headers. OpenAI behavior is unchanged.

### D7. Endpoint fallback wraps the whole host-local protocol

For Auto, catalog lookup, session acquisition, and inference form one host-local transaction. For explicit selection, catalog validation and inference form a host-local transaction without session acquisition. If an individual-host transaction fails with a network error, 5xx, 404 protocol unavailability, or an exhausted existing inference retry, the service starts the corresponding fresh transaction on the business host. It does not reuse catalog data or a session token from the failed host.

Cancellation and `URLError.cancelled` propagate immediately with no retry or host fallback. OAuth 401/403 propagates after sanitization because the same credential cannot be repaired by changing host. HTTP 429 propagates without host fallback or arbitrary model selection. Other HTTP 4xx responses are terminal unless D8 explicitly classifies their stable provider code for one Auto recovery.

### D8. Protocol-specific recovery is bounded to one re-resolution

If Auto inference returns `model_not_supported` or `unsupported_api_for_model`, the service invalidates the matching catalog and session entries, fetches a new catalog, performs initial session acquisition without an old session header, and repeats inference once. If Auto inference returns HTTP 401, the service treats it as a possibly stale session: it invalidates only the session, performs one initial acquisition without an old session header, and repeats inference if acquisition succeeds. A 401/403 from that acquisition proves the OAuth credential is invalid and is terminal. These recoveries are outside the parser retry loop and share one hard per-translation recovery budget; at most one recovery inference occurs regardless of error sequence. A repeated error is surfaced through the existing sanitized provider error contract.

Malformed model-session responses and an empty compatible set are not retried against the same host; they proceed to host fallback once, then fail. Ordinary inference 5xx and parse failures keep the existing `ChatCompletionsClient` two-attempt behavior.

To make that boundary real, `ChatCompletionsClient` gains an injected API-error retry classifier with a default preserving current OpenAI behavior. Copilot configures the classifier so only transport failures and HTTP 5xx remain eligible for its existing two-attempt loop. HTTP 401, 403, 429, other 4xx responses, `model_not_supported`, and `unsupported_api_for_model` escape after the first inference request to the Copilot service's terminal/recovery state machine. Response parse failures retain the current two-attempt behavior. This classifier changes retry eligibility only; it does not move Copilot routing logic into the shared client.

### D9. Logging records routing decisions but never credentials

Successful Auto resolution logs one operational diagnostic containing the host's sanitized endpoint and resolved model ID. It must not include OAuth tokens, `Copilot-Session-Token`, model-session response bodies, request bodies, or the token fingerprint. Errors continue through `APIErrorSanitizer` and the existing 200-character/redaction contract.

### D10. TDD proceeds as vertical behavior slices

Implementation does not batch all tests before code. Each task slice follows:

1. RED: add one observable behavior test and run the narrow test target to prove it fails for the intended reason.
2. GREEN: add the smallest production change that passes that new test and all earlier slice tests.
3. REFACTOR: only after green, remove duplication or deepen the module without changing behavior, then rerun the same tests.

Tests exercise decoded catalog outputs, captured HTTP requests, public service translation calls, persisted preferences, and model-load state derivation. They do not assert private method calls or actor internals.

## Risks / Trade-offs

- [Risk] `/models/session` and the API version are undocumented and can change. -> Isolate constants and wire types in the Copilot boundary; fail explicitly on schema drift; cover exact headers, paths, and invariants with request-level tests.
- [Risk] Constraining hints to `/chat/completions` provides compatibility-based Auto rather than the full client router. -> State this limitation; add `/responses` in a separate change before allowing responses-only candidates.
- [Risk] The catalog can change between `/models` and `/models/session`. -> Validate `selected_model` against both the session's `available_models` and the compatible catalog; invalidate and reacquire once on drift.
- [Risk] Process-local shared cache can leak state between accounts or tests. -> Key by token digest and host; inject isolated caches in tests; never log keys; clear the entry on authentication/protocol failures.
- [Risk] A five-minute refresh window may refresh more often than strictly necessary. -> Prefer predictable validity; send the still-valid old session token only to the same host/account/hint key and single-flight the refresh.
- [Risk] Settings and translation can request the catalog independently. -> Share a five-minute process-local catalog store so calls coalesce without making Settings a prerequisite for translation.
- [Risk] A transient refresh failure can leave little time for inference on the old session. -> Recheck expiry after failure, use the old session only while strictly unexpired, and retain the one-shot inference-401 recovery path.
- [Risk] Filtering picker entries to `/chat/completions` hides models previously shown by the app. -> This is intentional because selecting a model the implemented transport cannot call is nonfunctional; full transport support is a separate feature.
- [Risk] Host fallback can cause an additional request sequence. -> Preserve existing individual-first compatibility and bound fallback to one attempt per host.

## Migration Plan

1. Land model decoding and catalog classification with no translation-path switch.
2. Land explicit Settings states and change the default preference to `auto`; preserve valid concrete selections.
3. Land the Auto session resolver behind the `auto` preference while keeping concrete selection behavior.
4. Land bounded invalidation/recovery and host-local fallback tests.
5. Run the focused Copilot, Preferences, and Settings tests after every vertical slice.
6. Run the complete MangaTranslator scheme.
7. Perform one manual Student-account smoke test: open Settings, confirm fixed Auto presentation, translate a page, confirm success, and inspect sanitized logs for the concrete model with no token material.

Rollback is a normal code revert. No database or irreversible preference migration is introduced. A stored `auto` value on older code would fail, so release rollback must also reset `copilotModel` to a supported concrete value or ship a small backward-compatibility guard.

## Open Questions

None for this change. `/responses` support and full task-intent routing are explicitly deferred rather than left as implementation choices.
