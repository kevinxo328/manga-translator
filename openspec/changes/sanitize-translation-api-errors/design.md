## Context

Translation provider services currently treat non-2xx HTTP responses as raw text and pass the full body into `TranslationError.apiError`. `TranslationViewModel` writes `error.localizedDescription` into page state, and `ContentView` displays that state in the `Translation Failed` overlay. This creates a direct path from provider response body to UI.

The app already has a safer diagnostic path through `DebugLogger.logAPIDiagnostic`, which stores structured metadata and sanitizes endpoints. That path intentionally excludes raw API response bodies. The missing piece is a shared provider error boundary that extracts useful provider/status/code/message diagnostics without carrying raw response payloads.

The affected providers are OpenAI Compatible, GitHub Copilot, Google Translate, and DeepL. The provider error formats are not identical, and GitHub Copilot does not have a stable public REST error schema for the chat completions endpoint, so parsing must be best-effort with safe fallback behavior.

## Goals / Non-Goals

**Goals:**

- Prevent raw provider response bodies from entering UI state, `localizedDescription`, or persisted debug logs.
- Keep UI errors actionable by showing provider name, HTTP status, stable code when available, and a sanitized provider message when available.
- Keep logs useful by storing redacted provider error semantics, not just generic HTTP status.
- Apply one sanitizer boundary consistently across OpenAI Compatible, GitHub Copilot, Google Translate, and DeepL.
- Preserve existing behavior for missing credentials, invalid success-body parsing, network errors, OCR errors, cache errors, archive errors, and model lifecycle errors.
- Add deterministic HTTP test seams for provider non-2xx responses.

**Non-Goals:**

- Do not redesign the full translation protocol.
- Do not localize provider error messages.
- Do not persist full raw provider response bodies, even in debug logs.
- Do not change archive import, OCR, cache, or model lifecycle error contracts.
- Do not introduce external dependencies for redaction or parsing.

## Decisions

### Decision: Use a structured sanitized provider API error

`TranslationError.apiError` will carry a structured sanitized payload instead of a raw string. The payload includes provider, HTTP status, optional code, and optional sanitized message.

Rationale: a raw string overload makes it too easy for future call sites and tests to reintroduce raw body leakage. A structured payload gives UI and logging code stable fields and makes tests precise.

Alternative considered: keep `apiError(String)` and require providers to pass sanitized strings. That is smaller but weaker because the type system cannot distinguish raw and safe strings.

### Decision: Provider services own non-2xx parsing before throwing

Each translation provider will parse non-2xx response data into `SanitizedAPIError` at the HTTP boundary. The thrown error must already be safe for UI and logging.

Rationale: the HTTP call site has provider, endpoint, model, status, and response data together. Sanitizing there prevents unsafe data from crossing service boundaries.

Alternative considered: sanitize in `TranslationViewModel`. That would protect the current UI path but would still allow raw provider data through tests, logs, or future callers.

### Decision: Log redacted provider error semantics, not raw bodies

Debug logs should include provider, HTTP status, safe code, redacted provider message, model, and sanitized endpoint. They must not include raw response body, full request body, authorization headers, API keys, OAuth tokens, query secrets, or emails.

Rationale: users need to diagnose real provider failures, but raw bodies are not a safe persistence format. The sanitized provider message preserves the useful semantic content while removing sensitive substrings and bounding length.

Alternative considered: do not log provider messages at all. That is safer but makes real-world provider failures difficult to diagnose from the app's debug UI.

### Decision: Use provider-specific parsers with generic fallback

Parsing priority:

- OpenAI Compatible: `error.code`, then `error.type`; message from `error.message`.
- GitHub Copilot: OpenAI-compatible first, then top-level `code`; message from `error.message`, then top-level `message`.
- Google Translate: `error.status`, then first `error.errors[].reason`, then numeric `error.code`; message from `error.message`.
- DeepL: string `code` only if present; message from top-level `message`.
- Generic fallback: top-level `code` or `error_code`; message from top-level `message`, `error_description`, or sanitized body text.

Rationale: this matches current provider families without requiring strict schemas for every deployment or OpenAI-compatible server.

Alternative considered: only parse one generic shape. That would lose stable Google and DeepL diagnostics and make UI less actionable.

### Decision: Keep ViewModel behavior narrow

The ViewModel should keep forwarding `error.localizedDescription` for existing error families. The safety guarantee for provider API errors comes from `TranslationError.apiError` no longer being constructible with raw body strings.

Rationale: this avoids broad, speculative redaction of unrelated OCR/cache/model errors. The provider API path is the known leakage source.

Alternative considered: add a universal ViewModel redaction pass. That may hide useful local errors and still cannot reliably distinguish sensitive from non-sensitive text in arbitrary errors.

## Risks / Trade-offs

- [Risk] Sanitization removes too much useful provider detail. -> Mitigation: preserve provider, HTTP status, code, and a redacted/truncated message; add tests for actionable examples.
- [Risk] Sanitization misses an unknown credential format. -> Mitigation: combine specific patterns for known keys with conservative long-token and query-secret redaction.
- [Risk] Copilot response shape changes. -> Mitigation: parse OpenAI-compatible first and fall back to generic JSON/text extraction without exposing raw body.
- [Risk] Existing tests or fakes rely on `TranslationError.apiError(String)`. -> Mitigation: update tests to construct `SanitizedAPIError`, making the safe boundary explicit.
- [Risk] Logging sanitized provider messages could still include unexpected sensitive content. -> Mitigation: apply the same sanitizer used for UI before logging and keep the 200-character bound.

## Migration Plan

1. Add `APIErrorSanitizer` and tests for redaction, truncation, provider-specific parsing, and fallback parsing.
2. Change `TranslationError.apiError` to accept only sanitized structured payloads.
3. Update provider services to inject `URLSession` defaults for testing and to sanitize non-2xx responses before throwing.
4. Add safe API error diagnostic logging from provider non-2xx paths.
5. Update ViewModel tests and provider tests to assert no raw body reaches page state, `localizedDescription`, or debug logs.
6. Run the targeted provider, ViewModel, and debug log tests.

Rollback is limited to reverting this change before release. No persisted data migration is required.

## Open Questions

(none)
