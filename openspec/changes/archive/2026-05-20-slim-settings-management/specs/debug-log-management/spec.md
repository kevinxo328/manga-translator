## ADDED Requirements

### Requirement: Debug tab UI in Settings
The Settings view SHALL provide a dedicated Debug tab for inspection and management of app-owned persistent debug logs. The tab SHALL display log results in a SwiftUI list with at most 100 initially loaded rows, support filtering by level, category, session, and free text, support paged loading up to a 500-row visible cap, debounce search input, surface log details via a detail sheet, keep full content text out of list rows, present clear confirmations with match counts, preserve active filters across clear actions, and export through an `NSSavePanel` with a default `.ndjson` filename. This requirement owns the Settings-tab user flow; data-layer concerns (pagination, retention, isolation, sensitive-payload exclusion) are owned by the other requirements in this capability.

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
