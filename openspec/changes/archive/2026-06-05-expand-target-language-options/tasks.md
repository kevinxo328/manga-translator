## 1. Tests

- [x] 1.1 Add model tests for expanded `Language` cases, display labels, raw values, source ordering, and target ordering.
- [x] 1.2 Add Google Translate request-body tests that verify provider codes for expanded target languages.
- [x] 1.3 Add DeepL request-body tests that verify provider codes for expanded target languages.

## 2. Language Model

- [x] 2.1 Add language enum cases for French, German, Indonesian, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, and Vietnamese.
- [x] 2.2 Update `Language.displayName` with flag emoji and full English names for all supported languages.
- [x] 2.3 Update `Language.sourceLanguages` to A-Z order and add `Language.targetLanguages` in the specified A-Z order.

## 3. UI Integration

- [x] 3.1 Update `ContentView` target picker to use `Language.targetLanguages`.
- [x] 3.2 Update `SettingsView` target picker to use `Language.targetLanguages`.

## 4. Provider Integration

- [x] 4.1 Extend Google Translate language-code mapping for every target language.
- [x] 4.2 Extend DeepL language-code mapping for every target language.
- [x] 4.3 Confirm LLM prompt output uses the expanded language display names without additional routing changes.

## 5. Documentation and Verification

- [x] 5.1 Update `README.md` supported language documentation.
- [x] 5.2 Run focused model and provider tests.
- [x] 5.3 Run the main `MangaTranslator` test scheme or document why it could not be run.
  - Could not run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS'`: Xcode failed before compilation because `IDESimulatorFoundation` could not load `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/.../CoreSimulator`, reported as blocked by the sandbox. `xcodebuild -runFirstLaunch` also failed with `Install Failed: Failed to create install request.`
