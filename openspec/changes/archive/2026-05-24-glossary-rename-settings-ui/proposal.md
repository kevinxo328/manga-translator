## Why

Currently, translation glossaries in MangaTranslator cannot be renamed once created, which limits user flexibility. Additionally, managing glossaries inside a floating modal sheet feels detached from the app's native configuration system. This change introduces a rename feature (limited to 20 characters) and integrates a polished, native grouped-style glossary editor directly inside the central macOS `SettingsView` window.

## What Changes

- **Add Glossary Renaming**: Introduce `renameGlossary` in `GlossaryService`. Glossary names are trimmed before validation, empty or whitespace-only names throw a validation error, and names longer than 20 characters are truncated to 20 characters before persistence.
- **Settings UI Integration**: Add a dedicated **Glossary** tab to `SettingsView` with a beautiful `.formStyle(.grouped)` form matching other preference panes.
- **Sheet-based Rename**: Allow renaming the active glossary via a pre-filled sheet in the Settings panel. The ✏️ button opens the sheet; the Rename button commits and closes it; Cancel leaves the existing name unchanged.
- **Embedded Style Alignment**: Refactor `GlossaryView` with an `isEmbedded` parameter to seamlessly render as native grouped form rows (Source -> Target) with hover edit/delete actions and a clean term-adding row.
- **Toolbar Deep-linking**: Update the main window's `Manage Glossaries...` toolbar menu action to deep-link straight to the settings' Glossary tab using an in-memory `activeTabIdentifier` in `PreferencesService`.

## Capabilities

### New Capabilities

*(None)*

### Modified Capabilities

- `glossary-management`: Adding rename requirements, enforcing name character limits, and migrating the management UI from a modal sheet to the unified settings window.
- `settings-management`: Introducing a new Glossary settings tab and supporting programmatic active tab switching from the main window.

## Impact

- **Affected Code**: `GlossaryService`, `PreferencesService`, `SettingsView`, `GlossaryView`, `ContentView`, `MangaTranslatorApp`.
- **Database/SQLite**: Adds an `UPDATE` operation to `glossaries` table.
- **Testing**: Adds test coverage for renaming constraints, empty-input protection, name truncation, non-persistent settings tab routing, and the main-window-to-Glossary-tab deep-link.
