## Why

The current language display labels ("Japanese", "English", "Traditional Chinese") are too long for the limited space in the toolbar and settings UI. This results in an overcrowded layout and potential text truncation, especially in the 80px wide buttons used in the header.

## What Changes

Refactor the `Language` model to use international standard short codes for its display name. This ensures a consistent, professional, and space-efficient UI across the application.

- Change `displayName` for `.ja` from "Japanese" to "JA".
- Change `displayName` for `.en` from "English" to "EN".
- Change `displayName` for `.zhHant` from "Traditional Chinese" to "ZH-TW".

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `settings-management`: Update language selection UI to use international standard short codes for consistency and space efficiency.

## Impact

- **Affected Code**: `MangaTranslator/Models/Models.swift` (model definition).
- **UI Impact**: `MangaTranslator/Views/ContentView.swift` (header toolbar) and `MangaTranslator/Views/SettingsView.swift` (preferences tab) will automatically show the new short codes.
