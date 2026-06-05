## Why

The app currently exposes only Japanese, English, and Traditional Chinese as target languages, which is too narrow for common manga translation use. Expanding target languages gives users useful coverage while keeping source languages constrained to OCR-supported languages.

## What Changes

- Keep source languages limited to English and Japanese.
- Sort both source and target language pickers A-Z by English language name.
- Add target-language support for French, German, Indonesian, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, and Vietnamese.
- Introduce an explicit target-language list so target picker behavior is not coupled to `Language.allCases`.
- Update provider language-code mappings for Google Translate and DeepL.
- Update tests and documentation for the expanded language set and ordering.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `translation-service`: Expand supported target languages and provider language-code coverage.
- `settings-management`: Update language picker contents and ordering.

## Impact

- Affected code: `Language` model, `ContentView`, `SettingsView`, Google and DeepL translation services.
- Affected tests: language model tests, provider request-body tests, and any picker expectation tests.
- Affected docs/specs: `README.md`, `translation-service`, and `settings-management`.
