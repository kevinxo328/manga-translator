## Why

Translation providers currently surface non-2xx response bodies through `TranslationError.apiError`, and `TranslationViewModel` forwards `localizedDescription` into page error UI. Provider response bodies can contain credentials, email addresses, echoed request details, or other sensitive payloads, so raw bodies must not cross into UI state or persisted diagnostics.

At the same time, users still need actionable failures and debuggable logs. The change formalizes a safe error contract: UI receives bounded provider/status/code/message summaries, and debug logs retain the redacted provider error semantics without persisting raw response bodies.

## What Changes

- Replace raw-string provider API errors with structured sanitized API errors.
- Sanitize provider error messages before they can enter `localizedDescription`, page state, or debug logs.
- Apply the same non-2xx error boundary to OpenAI Compatible, GitHub Copilot, Google Translate, and DeepL.
- Define provider-specific best-effort parsing for OpenAI-compatible, Copilot, Google, and DeepL error response shapes.
- Preserve existing user-facing behavior for missing credentials, invalid success-body parsing, network errors, OCR errors, cache errors, archive errors, and model lifecycle errors.
- Extend API diagnostics so logs can include provider, HTTP status, safe code, redacted provider message, model, and sanitized endpoint, while still excluding raw response bodies and credentials.
- Add test seams for provider HTTP clients so non-2xx responses can be covered with deterministic `URLProtocol` tests.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `translation-service`: Defines the sanitized provider API error contract, UI-facing error formatting, provider-specific error parsing, and non-2xx bridging for all translation providers.
- `debug-log-management`: Clarifies that API error diagnostics may persist redacted provider error semantics but must not persist raw response bodies, credentials, or query secrets.

## Impact

- Affected code:
  - `MangaTranslator/Services/APIErrorSanitizer.swift`
  - `MangaTranslator/Services/TranslationError.swift`
  - `MangaTranslator/Services/OpenAITranslationService.swift`
  - `MangaTranslator/Services/DeepLTranslationService.swift`
  - `MangaTranslator/Services/GoogleTranslationService.swift`
  - `MangaTranslator/Services/CopilotTranslationService.swift`
  - `MangaTranslator/Services/DebugLogger.swift`
  - `MangaTranslator/ViewModels/TranslationViewModel.swift`
- Affected tests:
  - `MangaTranslatorTests/OpenAITranslationServiceTests.swift`
  - `MangaTranslatorTests/DeepLTranslationServiceTests.swift`
  - `MangaTranslatorTests/GoogleTranslationServiceTests.swift`
  - `MangaTranslatorTests/CopilotTranslationServiceTests.swift`
  - `MangaTranslatorTests/TranslationViewModelTests.swift`
  - `MangaTranslatorTests/DebugLogStoreTests.swift`
  - `MangaTranslatorTests/DebugLogGuardTests.swift`
- Internal API impact:
  - `TranslationError.apiError(String)` becomes structured and no longer accepts raw response bodies.
  - Translation provider initializers may gain `URLSession` default parameters for test injection.
- Dependencies:
  - No new external dependencies expected.
