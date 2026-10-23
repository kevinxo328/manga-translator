# Domain glossary

## Local open-source distribution

MangaTranslator is distributed as open-source software that runs translation
requests directly from the user's macOS device. It does not proxy, host, or
operate those requests as a remote service on the user's behalf.

## ChatGPT Plan translation engine

A translation engine that uses a user-authorized ChatGPT plan through Sign in
with ChatGPT. It is distinct from both the API-key-based OpenAI-compatible
engine and Codex CLI authentication.

## Linked ChatGPT account

The one ChatGPT account authorized for the ChatGPT Plan translation engine on a
device. Replacing it requires signing out of the current account before
authorizing another account. Settings displays its verified email only as a
local account identifier and never includes it in diagnostics or translation
logs.

## ChatGPT Plan model catalog

The current account-specific list of models that the Linked ChatGPT account may
select for translation. MangaTranslator presents this list, selects its first
entry by default, persists an explicit selection, and never silently
substitutes a different model. It refreshes when its Settings controls appear,
uses a five-minute in-memory cache, and provides an explicit retry action.

## ChatGPT Plan availability failure

A translation failure caused by exhausted plan usage, account ineligibility, or
revoked authorization. It stops the current translation batch and preserves
untranslated items; MangaTranslator never silently falls back to another
provider or presents a special recovery flow.

## ChatGPT Plan sign-in

An explicit user-initiated authorization flow started from Settings. The main
translation UI never opens the browser automatically and reports an ordinary
provider error if the selected engine is not signed in.

## ChatGPT Plan sign-out

An explicit Settings action that revokes the current renewable OAuth session
and removes its local credential record, so the Linked ChatGPT account is no
longer available to MangaTranslator.

## ChatGPT Plan preview

The ChatGPT Plan translation engine is presented as a Preview feature because
OpenAI's eligibility, plan limits, model catalog, and request contract may
change. This label communicates an external-service constraint, not reduced
translation correctness. Its Settings controls appear in the API Keys tab after
API-key providers and before GitHub Copilot.

## ChatGPT Plan inference path

The translation engine calls the OpenAI Responses API directly with the Linked
ChatGPT account's OAuth access token. It does not use Codex app-server.

## ChatGPT Plan translation context

Every ChatGPT Plan translation request includes the same current-page bubbles,
glossary terms, and recent-page summaries used by the OpenAI-compatible
engine. No context is assumed to persist remotely between requests.

## ChatGPT Plan structured-output capability

The per-model, time-limited result of attempting strict structured output on
the ChatGPT Plan Responses path. An unsupported capability is distinct from a
temporary translation failure: it selects the compatible request format for
seven days, without changing the user's selected model or translation engine.
