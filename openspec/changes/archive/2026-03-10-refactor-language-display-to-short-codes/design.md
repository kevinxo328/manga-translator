## Context

The `Language` enum in `MangaTranslator/Models/Models.swift` currently provides user-facing labels through the `displayName` property. These labels are long English names (e.g., "Traditional Chinese"), which exceed the available space in the UI, particularly in the 80px toolbar buttons and the settings picker.

## Goals / Non-Goals

**Goals:**
- Standardize language display to international standard short codes (JA, EN, ZH-TW) for a more professional and space-efficient UI.
- Ensure consistent display across the toolbar and settings views.

**Non-Goals:**
- Modifying the internal `rawValue` or `visionLanguageCode` properties, which are used for API integration and OCR.
- Implementing a complete localization/i18n framework for the entire application.

## Decisions

### 1. Directly Update `Language.displayName`
We will modify the `displayName` property of the `Language` enum to return short codes instead of full names.
- **Rationale**: This is the most surgical approach. Since `ContentView` and `SettingsView` already use `displayName`, no UI-side logic changes are required.
- **Alternatives Considered**: Creating a new `shortCode` property and updating all UI call sites. This was rejected because the user explicitly wants the same display in both the header and settings, and modifying `displayName` is more efficient.

### 2. Standardized Short Codes
- `.ja` -> **JA**
- `.en` → **EN**
- `.zhHant` → **ZH-TW**
- **Rationale**: These follow common ISO 639-1 / 3166-1 patterns. `ZH-TW` is used for Traditional Chinese to clearly distinguish it from Simplified Chinese (`ZH-CN`) in future expansions.

### 3. Maintain UI Layout
The fixed width of 80px for the language picker buttons in `ContentView.swift` will be preserved.
- **Rationale**: The user requested that the space remain unchanged. The shorter labels will result in more whitespace, which improves visual clarity and professional appearance.

## Risks / Trade-offs

- **[Risk]** Some users may prefer full language names for clarity.
- **[Mitigation]** The chosen codes (JA, EN, ZH-TW) are standard in translation and software contexts. The 80px button width provides enough space for these codes to be clearly legible and aesthetically pleasing.
