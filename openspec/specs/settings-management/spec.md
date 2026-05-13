## Purpose

User preferences persistence and settings UI.

## Requirements

### Requirement: Store user preferences in UserDefaults
The system SHALL persist user preferences (default source language, default target language, default translation engine, concurrent translation limit, OpenAI base URL, OpenAI model name, GitHub Copilot model name) using UserDefaults.

#### Scenario: Preferences persist across launches
- **WHEN** user sets default language pair to Japanese → Traditional Chinese and quits the app
- **THEN** the app launches with Japanese → Traditional Chinese pre-selected

#### Scenario: OpenAI base URL persists across launches
- **WHEN** user sets the OpenAI base URL to `https://custom-api.example.com/v1` and quits the app
- **THEN** the app launches with the custom base URL pre-filled

### Requirement: Store API keys in Keychain
The system SHALL store translation service API keys (DeepL, Google, OpenAI) in the macOS Keychain using the Security framework. Keys SHALL be stored per-service using a stable, fixed service name constant ("com.chunweiliu.MangaTranslator") that does not change across build variants, TestFlight builds, or re-signing, ensuring credential continuity across app updates.

#### Scenario: Save API key
- **WHEN** user enters their DeepL API key in settings
- **THEN** the key is stored in Keychain and persists across app launches

#### Scenario: Retrieve API key
- **WHEN** user initiates a DeepL translation
- **THEN** the system retrieves the DeepL API key from Keychain

### Requirement: Settings UI
The system SHALL provide a settings view (accessible via Cmd+,) where users can configure API keys, default language pair, default translation engine, and update preferences. The view SHALL also provide a dedicated Debug tab for inspection and management of app-owned persistent debug logs. The Preferences tab SHALL include an "Updates" section with a toggle for automatic update checking and a "Check for Updates Now" button. The OpenAI section SHALL be renamed to "OpenAI Compatible" and SHALL include a Base URL text field, a free-text Model field, and "Reset" buttons for both fields. The `UpdateSettingsView` component SHALL own its `CheckForUpdatesViewModel` using `@StateObject` to ensure the ViewModel is retained across parent re-renders. All language selection pickers SHALL display languages using international standard short codes (e.g., JA, EN, ZH-TW) for consistency and space efficiency. The API Keys tab SHALL include a GitHub Copilot section that displays the availability status of the Copilot CLI and, when available, a model picker populated from the Copilot API. The engine picker in the Preferences tab SHALL only show the GitHub Copilot option when the Copilot CLI is installed and logged in.

#### Scenario: Open settings
- **WHEN** user presses Cmd+,
- **THEN** the settings window opens showing API key fields, default preferences, and update preferences

#### Scenario: Toggle automatic updates
- **WHEN** user toggles the automatic update check setting
- **THEN** the preference is persisted and Sparkle respects the new setting on next launch

#### Scenario: Manual update check from settings
- **WHEN** user clicks "Check for Updates Now" in the Preferences tab
- **THEN** Sparkle performs an update check and displays the result

#### Scenario: OpenAI Compatible section layout
- **WHEN** user views the API Keys tab
- **THEN** the section header SHALL display "OpenAI Compatible" with a brain icon
- **AND** the section SHALL contain an API Key secure field, a Base URL text field with a "Reset" button, and a Model text field with a "Reset" button

#### Scenario: UpdateSettingsView ViewModel survives parent re-render
- **WHEN** `SettingsView` body is re-evaluated (e.g., due to preference change)
- **THEN** `UpdateSettingsView` retains the same `CheckForUpdatesViewModel` instance

#### Scenario: Language picker display codes
- **WHEN** user opens the language selection picker in settings or the toolbar
- **THEN** the options SHALL be displayed as JA, EN, and ZH-TW

#### Scenario: GitHub Copilot section — CLI detected
- **WHEN** user opens the API Keys tab and the Copilot CLI is installed and logged in
- **THEN** a green checkmark label "Copilot CLI detected" is shown with a model picker populated from the Copilot API

#### Scenario: GitHub Copilot section — CLI not installed
- **WHEN** user opens the API Keys tab and the Copilot CLI binary is not found
- **THEN** a label "GitHub Copilot CLI not found" is shown with installation instructions

#### Scenario: GitHub Copilot section — not logged in
- **WHEN** user opens the API Keys tab and the CLI is installed but no keychain token exists
- **THEN** a warning "Not logged in" is shown with instructions to run `copilot login`

#### Scenario: Engine picker hides Copilot when unavailable
- **WHEN** user opens the engine picker in the Preferences tab and Copilot CLI is not installed or not logged in
- **THEN** the "GitHub Copilot" option is not shown in the picker

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

### Requirement: High-accuracy OCR settings section
The system SHALL display a "High-Accuracy OCR" section in SettingsView exclusively on Apple Silicon (`#if arch(arm64)`). The section SHALL be hidden entirely on Intel. The section SHALL reflect the current `ModelDownloadService.state` and update reactively as state changes.

#### Scenario: Intel device
- **WHEN** the app runs on an Intel Mac
- **THEN** the High-Accuracy OCR section is not visible in Settings

#### Scenario: Apple Silicon, not downloaded
- **WHEN** the device is Apple Silicon and the model has not been downloaded
- **THEN** the section shows a "Download and Enable" button

#### Scenario: Apple Silicon 8GB, not downloaded
- **WHEN** the device is Apple Silicon with 8GB RAM and the model has not been downloaded
- **THEN** the section shows the "Download and Enable" button and a warning label about RAM

#### Scenario: Download in progress
- **WHEN** model download is in progress
- **THEN** the section shows a progress indicator and a "Cancel" button; "Download and Enable" is hidden

#### Scenario: Model downloaded and enabled
- **WHEN** the model is downloaded and high-accuracy OCR is enabled
- **THEN** the section shows an enabled indicator, a "Disable" button, and a "Delete Model Data" button

#### Scenario: Model downloaded and disabled
- **WHEN** the model is downloaded and high-accuracy OCR is disabled
- **THEN** the section shows a disabled indicator, an "Enable" button, and a "Delete Model Data" button

### Requirement: Confirm before deleting model data
The system SHALL present a confirmation dialog before deleting the model. The dialog SHALL use English text. Deletion SHALL only proceed after user confirmation.

#### Scenario: User confirms deletion
- **WHEN** user clicks "Delete Model Data" and then confirms in the dialog
- **THEN** `ModelDownloadService.delete()` is called and state transitions to `.notDownloaded`

#### Scenario: User cancels deletion
- **WHEN** user clicks "Delete Model Data" but cancels in the confirmation dialog
- **THEN** no deletion occurs and state is unchanged

### Requirement: Persist high-accuracy OCR preference
The system SHALL persist the user's high-accuracy OCR enabled/disabled preference in `UserDefaults` under the key `paddleocr.enabled`. The system SHALL notify `MangaOCRService` to reset its recognizer when this preference changes. The system SHALL NOT allow `paddleocr.enabled = true` unless the model is downloaded and verified.

#### Scenario: Preference persists across launches
- **WHEN** user enables high-accuracy OCR and relaunches the app
- **THEN** high-accuracy OCR remains enabled if the model is still present

#### Scenario: Enable blocked when model is absent
- **WHEN** the model is not downloaded (or fails verification) and user attempts to enable high-accuracy OCR
- **THEN** `paddleocr.enabled` remains `false`, Settings keeps the disabled/not-downloaded state, and the UI displays actionable guidance ("Download model first")

#### Scenario: Enable blocked after failed verification
- **WHEN** model verification fails and user attempts to enable high-accuracy OCR
- **THEN** enable is rejected, an error message explains model integrity failure, and the UI offers re-download guidance

#### Scenario: Preference resets when model deleted
- **WHEN** the model is deleted
- **THEN** `paddleocr.enabled` is set to `false` in `UserDefaults`

### Requirement: Validate API key presence before translation
The system SHALL check that the required API key exists before attempting translation. If the key is missing, the system SHALL prompt the user to enter it in settings.

#### Scenario: Missing API key
- **WHEN** user selects DeepL engine but has not entered an API key
- **THEN** the system shows an alert directing the user to settings to enter the key

### Requirement: Settings changes apply immediately to active translation session
The system SHALL use a single shared `PreferencesService` instance across the Settings window and the translation pipeline, so that any preference change (language pair, engine, model) is reflected in the next translation without requiring an app restart.

#### Scenario: Language change applies to next translation
- **WHEN** user changes the target language in Settings
- **THEN** the next translation run uses the updated target language

#### Scenario: Engine change applies to next translation
- **WHEN** user changes the translation engine in Settings
- **THEN** the next translation run uses the updated engine

#### Scenario: Model change applies to next translation
- **WHEN** user changes the OpenAI model in Settings
- **THEN** the next translation run uses the updated model identifier
