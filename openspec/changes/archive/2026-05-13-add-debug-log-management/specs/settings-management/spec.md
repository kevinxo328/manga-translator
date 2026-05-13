## MODIFIED Requirements

### Requirement: Settings UI
The system SHALL provide a settings view (accessible via Cmd+,) where users can configure API keys, default language pair, default translation engine, and update preferences. The view SHALL also provide a dedicated Debug tab for inspection and management of app-owned persistent debug logs. The Preferences tab SHALL include an "Updates" section with a toggle for automatic update checking and a "Check for Updates Now" button. The OpenAI section SHALL be renamed to "OpenAI Compatible" and SHALL include a Base URL text field, a free-text Model field, and "Reset" buttons for both fields. The `UpdateSettingsView` component SHALL own its `CheckForUpdatesViewModel` using `@StateObject` to ensure the ViewModel is retained across parent re-renders. All language selection pickers SHALL display languages using international standard short codes (e.g., JA, EN, ZH-TW) for consistency and space efficiency. The API Keys tab SHALL include a GitHub Copilot section that displays the availability status of the Copilot CLI and, when available, a model picker populated from the Copilot API. The engine picker in the Preferences tab SHALL only show the GitHub Copilot option when the Copilot CLI is installed and logged in.

#### Scenario: Open Debug tab
- **WHEN** user opens Settings and selects the Debug tab
- **THEN** the app SHALL display controls to inspect app-owned persistent debug logs

#### Scenario: Filter logs from Settings
- **WHEN** user applies a level, category, session, or text filter in the Debug tab
- **THEN** the displayed log list SHALL update to match the active filter

#### Scenario: Debug tab uses bounded list
- **WHEN** user opens the Debug tab
- **THEN** the app SHALL display log results in a SwiftUI list with at most 100 initially loaded rows

#### Scenario: Debug tab preserves Settings window size
- **WHEN** the Debug tab is added to Settings
- **THEN** V1 SHALL preserve the existing Settings window dimensions
- **THEN** the Debug tab SHALL use compact controls, bounded results, and detail sheets to fit the existing window

#### Scenario: Load more logs
- **WHEN** user clicks Load More in the Debug tab
- **THEN** the app SHALL append the next 100 matching rows up to a visible cap of 500 rows

#### Scenario: Open log detail
- **WHEN** user selects a log row
- **THEN** the app SHALL open a detail sheet with full message, metadata, file path, session id, and source context

#### Scenario: Content text stays out of rows
- **WHEN** a content log appears in the list
- **THEN** the row SHALL show only a compact summary
- **THEN** full OCR or translated text SHALL be shown in the detail sheet

#### Scenario: Search is debounced
- **WHEN** user types into the Debug tab search field
- **THEN** the app SHALL debounce query reloads before reading the persistent log store

#### Scenario: Clear logs from Settings
- **WHEN** user confirms clearing logs from the Debug tab
- **THEN** the matching app-owned persistent log entries SHALL be deleted

#### Scenario: Clear confirmation shows count
- **WHEN** user starts a clear action from the Debug tab
- **THEN** the confirmation SHALL show the number of matching persistent log entries that will be deleted

#### Scenario: Clear preserves filters
- **WHEN** user clears matching logs from the Debug tab
- **THEN** the app SHALL keep the active filters and reload the result list

#### Scenario: Export logs from Settings
- **WHEN** user requests export from the Debug tab
- **THEN** the app SHALL export the currently selected persistent log dataset

#### Scenario: Export uses save panel
- **WHEN** user requests export from the Debug tab
- **THEN** the app SHALL present an `NSSavePanel` with a default `.ndjson` filename
