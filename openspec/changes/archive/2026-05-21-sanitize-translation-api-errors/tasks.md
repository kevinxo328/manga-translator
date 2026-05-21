## 1. Sanitizer Tests

- [x] 1.1 Add `APIErrorSanitizer` unit tests for removing authorization header values, bearer/API keys, OAuth tokens, long opaque token-like strings, query secrets, and email addresses.
- [x] 1.2 Add sanitizer tests proving messages are normalized and truncated to the 200-character bound after redaction.
- [x] 1.3 Add parser tests for OpenAI-compatible error bodies using `error.code`, `error.type`, and `error.message`.
- [x] 1.4 Add parser tests for Google error bodies using `error.status`, `error.errors[].reason`, numeric `error.code`, and `error.message`.
- [x] 1.5 Add parser tests for DeepL error bodies using the top-level `message` key.
- [x] 1.6 Add parser tests for Copilot OpenAI-compatible bodies and generic malformed text fallback.

## 2. Sanitizer Implementation

- [x] 2.1 Create `MangaTranslator/Services/APIErrorSanitizer.swift` with `SanitizedAPIError` fields for provider, status code, optional code, and optional sanitized message.
- [x] 2.2 Implement provider-specific parsing for OpenAI Compatible, GitHub Copilot, Google Translate, DeepL, and generic fallback.
- [x] 2.3 Implement redaction for authorization headers, bearer/API keys, OAuth tokens, long opaque tokens, URL query secrets, and email addresses.
- [x] 2.4 Implement UI-facing formatting for code/message, message-only, and status-only provider API errors.

## 3. Translation Error Bridge

- [x] 3.1 Change `TranslationError.apiError` from raw string payload to structured `SanitizedAPIError`.
- [x] 3.2 Update `TranslationError.errorDescription` to render only the sanitized provider API error summary.
- [x] 3.3 Update existing tests and fakes that construct `TranslationError.apiError("...")` to construct sanitized payloads instead.
- [x] 3.4 Confirm missing API key, invalid response, and network error descriptions keep their existing behavior.

## 4. Provider Service Integration

- [x] 4.1 Add `URLSession` default-parameter injection to `OpenAITranslationService`, `DeepLTranslationService`, `GoogleTranslationService`, and `CopilotTranslationService`.
- [x] 4.2 Update OpenAI Compatible non-2xx handling to parse and throw sanitized provider API errors.
- [x] 4.3 Update GitHub Copilot non-2xx handling to parse and throw sanitized provider API errors.
- [x] 4.4 Update Google Translate non-2xx handling to parse and throw sanitized provider API errors.
- [x] 4.5 Update DeepL non-2xx handling to parse and throw sanitized provider API errors.
- [x] 4.6 Ensure no provider service stores raw response body strings in thrown errors or debug metadata.

## 5. Provider Error Tests

- [x] 5.1 Add OpenAI Compatible non-2xx tests using injected `URLProtocol` responses with sensitive body content.
- [x] 5.2 Add GitHub Copilot non-2xx tests using OpenAI-compatible and generic fallback body shapes.
- [x] 5.3 Add Google Translate non-2xx tests covering `error.status`, `error.errors[].reason`, and sensitive message redaction.
- [x] 5.4 Add DeepL non-2xx tests covering top-level `message` parsing and sensitive message redaction.
- [x] 5.5 Assert each provider error `localizedDescription` includes provider/status/safe code/safe message when available.
- [x] 5.6 Assert each provider error `localizedDescription` excludes raw tokens, emails, query secrets, authorization values, and full raw body text.

## 6. UI and Logging Tests

- [x] 6.1 Add `TranslationViewModel` coverage proving sanitized provider API errors reach `PageState.error` without raw sensitive body content.
- [x] 6.2 Add debug log tests proving provider API error diagnostics persist provider category, HTTP status, safe code, redacted provider message, model, and sanitized endpoint.
- [x] 6.3 Add debug log tests proving provider API error diagnostics do not persist raw response bodies, credentials, query secrets, or emails.
- [x] 6.4 Keep `DebugLogGuardTests` passing so production logging still flows through the shared debug logger.

## 7. Safe Diagnostic Logging Implementation

- [x] 7.1 Extend `DebugLogger` only if needed with a dedicated API error diagnostic helper that accepts sanitized fields and never accepts raw response data.
- [x] 7.2 Log provider non-2xx failures with provider category, HTTP status, safe code, redacted provider message, model when applicable, and sanitized endpoint.
- [x] 7.3 Confirm endpoint logging strips embedded credentials, query strings, and fragments.

## 8. Verification

- [x] 8.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/OpenAITranslationServiceTests`.
- [x] 8.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/DeepLTranslationServiceTests`.
- [x] 8.3 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/GoogleTranslationServiceTests`.
- [x] 8.4 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/CopilotTranslationServiceTests`.
- [x] 8.5 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests`.
- [x] 8.6 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/DebugLogStoreTests`.
- [x] 8.7 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/DebugLogGuardTests`.
- [x] 8.8 Run `openspec validate sanitize-translation-api-errors --strict`.
