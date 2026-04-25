## ADDED Requirements

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

---

### Requirement: Confirm before deleting model data
The system SHALL present a confirmation dialog before deleting the model. The dialog SHALL use English text. Deletion SHALL only proceed after user confirmation.

#### Scenario: User confirms deletion
- **WHEN** user clicks "Delete Model Data" and then confirms in the dialog
- **THEN** `ModelDownloadService.delete()` is called and state transitions to `.notDownloaded`

#### Scenario: User cancels deletion
- **WHEN** user clicks "Delete Model Data" but cancels in the confirmation dialog
- **THEN** no deletion occurs and state is unchanged

---

### Requirement: Persist high-accuracy OCR preference
The system SHALL persist the user's high-accuracy OCR enabled/disabled preference in `UserDefaults` under the key `paddleocr.enabled`. The system SHALL notify `MangaOCRService` to reset its recognizer when this preference changes.

#### Scenario: Preference persists across launches
- **WHEN** user enables high-accuracy OCR and relaunches the app
- **THEN** high-accuracy OCR remains enabled if the model is still present

#### Scenario: Preference resets when model deleted
- **WHEN** the model is deleted
- **THEN** `paddleocr.enabled` is set to `false` in `UserDefaults`
