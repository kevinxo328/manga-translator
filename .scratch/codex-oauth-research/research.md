# ChatGPT-plan OAuth as a MangaTranslator translation engine

Researched: 2026-10-22  
Scope: whether MangaTranslator can add a translation engine backed by what is
often called “Codex OAuth,” without changing application code.

## Decision summary

**Feasible, with a terminology and product-scope correction.** The supported
integration is **Sign in with ChatGPT / ChatGPT plan usage**, not an API for
reusing Codex CLI credentials or an independent Codex translation API. After
user consent, an open-source, locally hosted application can send the user's
OAuth access token to the public Responses API for eligible inference requests.
Text translation is a normal inference use case.

MangaTranslator is a locally run, MIT-licensed repository, so it appears to
fit the documented open-source/local-app route. This conclusion assumes that
the shipped product remains local and open source. A paid edition or a service
that proxies/hosts translation remotely must not assume eligibility: OpenAI
directs those apps to its interest form instead. [Overview: ChatGPT plan usage](https://developers.openai.com/siwc/token-sharing-open-source)

## What is supported

OpenAI documents an OAuth flow where an open-source app requests permission to
use the user's ChatGPT plan for eligible `POST /v1/responses` calls. The grant
does **not** give access to the user's ChatGPT conversations or other account
context. Requests must use a model available to that signed-in account and the
OAuth access token as its Bearer credential. They must target the public
Responses endpoint, not ChatGPT `backend-api` endpoints. [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)

This is distinct from the Codex CLI sign-in mechanism. The supported path is
not to locate, copy, or parse Codex CLI credentials from a user's Keychain or
files. MangaTranslator must own its own user-authorized OAuth registration and
credential lifecycle.

## Required authorization and credential handling

For a first-time local/OSS registration, OpenAI specifies Authorization Code
with PKCE, launched in the system browser. The request uses
`client_id=dynamic_agent_client`, a stable app name in `agent_name_hint`, a
per-installation opaque and stable `ext_agent_host_id`, and an HTTP loopback
callback on `127.0.0.1`. The required plan-use scopes are `offline_access`,
`resource.invoke`, and `chatgpt.tokens.use.direct`, alongside OIDC identity
scopes. The callback returns an issued client ID; it must be saved and reused
for that user/account registration rather than using `dynamic_agent_client`
again. No client secret or Platform API key is required for this direct flow. [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)

Each saved ChatGPT account needs its own issued client ID, identity record,
access token, refresh token, and retained ID token. OpenAI requires protected
local storage and explicitly excludes browser storage, source control, logs,
analytics, and support transcripts. Refresh near expiry with the saved issued
client ID; refresh tokens rotate, so refreshes for one session must be
serialized. On sign-out, revoke the refresh token and clear local credentials. [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)

For macOS, this should mean storing all secret token material in the existing
`KeychainService` (with a credential record that can support multiple ChatGPT
accounts), while keeping the non-secret host ID and selected-account metadata
in appropriate local preferences. Do not overload the existing `.openAI`
single-string API-key entry: OAuth needs expiry, rotation, client registration,
and revocation semantics that an API key does not.

## Inference contract and impact on the current client

The plan-usage preview requires `store: false` and `stream: true` for every
HTTP Responses request. The complete context must be supplied in `input` for
each request; HTTP `previous_response_id` continuation is not available.
`instructions` or developer messages are accepted, but a system-role input
item is rejected. Several ordinary Responses options are unavailable, including
`max_output_tokens`, `temperature`, `top_p`, background mode, and persistent
conversation state. Text input is supported, which is sufficient for the
existing OCR-to-translation flow. [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

This has a concrete implementation consequence: `ChatCompletionsClient` already
knows the `/responses` path, but its current Responses payload sends
`max_output_tokens`, does not set `store`/`stream`, and expects one JSON body.
It therefore cannot be used unchanged for this provider. The smallest safe
implementation seam is a dedicated streaming Responses request/decoder used
only by the new OAuth engine, reusing the existing prompt builders and response
parsers. It should parse SSE deltas into the final text, then pass that text to
the current `LLMResponseParser`.

## Recommended architecture

Add a distinct engine concept named **ChatGPT Plan** (not “Codex OAuth”). Keep
the existing API-key-based OpenAI-compatible engine unchanged.

1. Introduce an OAuth account/session component responsible for dynamic
   registration, PKCE/state/nonce validation, loopback callback handling, token
   refresh serialization, revocation, and Keychain persistence.
2. Add a `ChatGPTPlanTranslationService` that obtains a valid access token,
   fetches/refreshes the account-specific model list when the account changes,
   and invokes `POST https://api.openai.com/v1/responses` with the constrained
   streaming payload.
3. Make account, model availability, quota exhaustion, consent denial, expired
   sessions, and reauthorization visible in Settings. The model catalogue is
   useful for a picker but is not an entitlement check; a successful inference
   request is the actual confirmation.
4. Keep MangaTranslator's existing rolling three-page context in `input` on
   every request, because the plan-use route does not offer HTTP persistence.
   Keep the existing three-page concurrency cap initially; handle 429/plan-limit
   responses as user-actionable failures and do not silently fall back to a
   different paid credential.

The direct Responses design is preferred. Codex app-server is supported with
the same OAuth token, but it introduces a bundled child process, JSON-RPC
threads, lifecycle/restart work, and a mandatory restart when the access token
is refreshed. Those agent-oriented capabilities do not help a text translation
engine. [Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)

## Product and operational risks

- **Preview and eligibility risk:** the documented feature is preview behavior,
  and model availability/limits vary by account. Make the engine opt-in and
  retain OpenAI API key, DeepL, Google, and Copilot providers as alternatives.
  A Plus account shares its five-hour plan limit across these apps; OpenAI says
  Pro does not have that particular five-hour limit. [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- **Request-shape risk:** no sampling/output-token controls, no non-streaming
  completion, and no Responses server-side conversation state in this route.
  The response parser must robustly collect SSE events and preserve the app's
  current JSON-output contract.
- **Security risk:** OAuth refresh tokens are higher-value, renewable secrets.
  Keychain storage, diagnostic redaction, logout revocation, refresh-race
  protection, and account separation are release blockers.
- **UX risk:** this is not a zero-config API-key field. It requires a browser
  consent flow, stable per-install host identity, account selection, clear plan
  usage attribution, and recovery when a user revokes access or exceeds plan
  limits.

## Recommended next steps

1. Confirm that the intended distribution remains a local, open-source app;
   if not, submit OpenAI's interest form before scheduling implementation.
2. Produce a small, test-only OAuth spike using a non-production ChatGPT
   account: authorize, store a credential record, refresh it, revoke it, list
   models, and make one streaming `store:false` Responses request. Do not use
   or inspect existing Codex CLI credentials.
3. Define the provider's user stories and Settings UX, then implement it as a
   separate engine with TDD. Cover callback validation, rotating refresh-token
   persistence, logout/revocation, SSE accumulation, request-field exclusion,
   and reauthorization/limit errors.
4. Before release, recheck the official preview limitations and eligibility
   terms because they may change independently of normal API-key behavior.

## Primary sources

- [Sign in with ChatGPT: plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source)
- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Codex app-server with a ChatGPT-plan token](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
