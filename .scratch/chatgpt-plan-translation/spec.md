# ChatGPT Plan translation engine

**Status:** ready-for-agent

## Problem Statement

MangaTranslator users who have a ChatGPT subscription cannot use their plan for
manga translation without separately creating and funding an OpenAI API key.
They need a local, open-source-app-compatible way to authorize one ChatGPT
account and use its eligible plan access as a translation engine.

## Solution

Add a ChatGPT Plan (Preview) translation engine backed by Sign in with ChatGPT.
The user explicitly signs in from Settings, authorizes the local app through
OAuth Authorization Code with PKCE, selects an account-available model, and
uses it for translation. The app calls the public Responses API directly with
the OAuth access token and consumes its SSE stream. Credentials remain local,
and the app never reads Codex CLI credentials, proxies requests, or silently
uses another provider.

## User Stories

1. As a MangaTranslator user with an eligible ChatGPT account, I want to sign
   in from Settings, so that I can translate without configuring an API key.
2. As a user, I want sign-in to open only after I explicitly request it, so that
   the app never unexpectedly opens my browser.
3. As a user, I want OAuth state, nonce, and PKCE validation, so that a browser
   callback cannot attach the wrong authorization to my app.
4. As a user, I want the app to retain one authorized ChatGPT account locally,
   so that I do not need to sign in every launch.
5. As a user, I want to see the verified email of the connected account, so that
   I can confirm which ChatGPT account MangaTranslator will use.
6. As a user, I want to log out from Settings, so that the app revokes and
   removes my local renewable credentials.
7. As a user, I want ChatGPT Plan controls labelled Preview, so that I know
   eligibility, limits, models, and request requirements may change.
8. As a user, I want to choose from models available to my signed-in account,
   so that I can control translation quality and style.
9. As a user, I want my selected model remembered, so that later translations
   use my preference.
10. As a user, I want a missing selected model to fail normally rather than be
    silently replaced, so that a model change is never hidden from me.
11. As a user, I want the model list refreshed when ChatGPT Plan Settings open
    and retryable after a failure, so that the picker remains usable without
    delaying each translation.
12. As a user, I want ChatGPT Plan translations to apply my glossary and recent
    page context, so that quality matches the existing LLM translation engine.
13. As a user, I want an unsigned-in or revoked ChatGPT Plan engine to return a
    normal provider error, so that the selected engine remains explicit.
14. As a user, I want plan-limit, eligibility, and model failures to stop the
    current batch without an automatic provider fallback, so that I do not incur
    unexpected costs or receive changed output.
15. As a privacy-conscious user, I want OAuth credentials and account identity
    protected locally and excluded from logs, so that renewable secrets and my
    email are not exposed.
16. As a user, I want a completed streaming response to produce the same
    translated-bubble result shape as existing LLM engines, so that the viewer,
    cache, and batch workflow behave consistently.

## Implementation Decisions

- Add a distinct ChatGPT Plan translation engine; do not alter the API-key-based
  OpenAI-compatible engine and do not reuse Codex CLI authentication.
- Treat the feature as a locally distributed, open-source-app integration. It
  directly calls the public Responses API and does not use Codex app-server.
- Use Authorization Code with PKCE, fresh state and nonce per authorization,
  an HTTP loopback callback on `127.0.0.1`, dynamic client registration, and a
  stable per-installation host identifier.
- Persist the one Linked ChatGPT account's issued client ID, validated identity,
  access token, refresh token, expiry, and selected model as one credential
  lifecycle. Refresh-token rotation is serialized; sign-out revokes then removes
  the credential record.
- Store secret and identity material in protected local storage. Keep only
  non-secret app preferences outside the credential record, and redact OAuth
  credentials, authorization URLs, and account email from logs.
- Place a ChatGPT Plan (Preview) section in the API Keys Settings tab after
  API-key providers and before GitHub Copilot. It contains explicit sign-in or
  connected-account/logout controls, the model picker, and a retryable catalog
  state.
- Fetch the account-specific model catalog using the OAuth access token when
  ChatGPT Plan Settings appear. Reuse the existing five-minute in-memory catalog
  refresh pattern and retain an explicit selected model; do not silently choose
  a replacement when it disappears.
- Send each inference request to the Responses API using the OAuth bearer token
  with the supported streaming request contract. Build a provider-specific SSE
  decoder and complete a translation only after a successful terminal event.
- Preserve existing glossary and recent-page context by supplying it with every
  request. Do not rely on remote conversation persistence.
- Treat missing authorization, revoked credentials, unavailable models,
  ineligible accounts, exhausted usage, and stream failures as ordinary provider
  errors. Preserve untranslated work, stop the affected batch, and never
  auto-fallback to a different provider.

## Testing Decisions

- Test observable provider behavior rather than SwiftUI internals or OpenAI
  implementation details.
- Use injectable OAuth transport, local credential storage, URL session, clock,
  callback listener, and SSE stream seams; automated tests must not require a
  real OpenAI account, browser, Keychain item, or network connection.
- Cover PKCE/state/nonce validation, issued-client reuse, token refresh
  serialization and rotation, secure logout/revocation, catalog filtering and
  five-minute caching, persisted model selection, supported request shape, SSE
  accumulation and terminal states, token redaction, and provider-error
  propagation.
- Test Settings through public state and actions, following the existing
  Copilot-model and Settings-tab tests. Test translation behavior through the
  existing TranslationService and view-model seams.

## Out of Scope

- Multiple concurrently stored ChatGPT accounts or an account switcher.
- Reading, importing, or sharing Codex CLI credentials.
- Codex app-server, child-process management, JSON-RPC, or agent tooling.
- Automatic fallback to API-key, Copilot, DeepL, or Google engines.
- Remote request proxying, paid hosted operation, or commercial-plan approval.
- A guaranteed model, quota, eligibility, or usage-reset promise beyond the
  selected account's current OpenAI response.

## Further Notes

This design follows the project's Local open-source distribution, Linked
ChatGPT account, ChatGPT Plan model catalog, availability-failure, preview,
inference-path, and translation-context terminology. ADR 0001 records the
direct Responses API decision. The official research record is in
`.scratch/codex-oauth-research/research.md` and must be rechecked before
release because the integration is previewed by OpenAI.
