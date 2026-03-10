## 1. Model Update

- [x] 1.1 Update `Language.displayName` in `MangaTranslator/Models/Models.swift` to return "JA", "EN", and "ZH-TW".

## 2. UI Verification

- [x] 2.1 Verify that the toolbar in `ContentView.swift` displays the new short codes ("JA", "EN", "ZH-TW") correctly within the 80px buttons.
- [x] 2.2 Verify that the `SettingsView` (Preferences tab) displays the new short codes in the source and target language pickers.

## 3. Automated Testing

- [x] 3.1 Update or add unit tests to verify that `Language.displayName` returns the correct short codes.
