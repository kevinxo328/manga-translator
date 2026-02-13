## MODIFIED Requirements

### Requirement: Automatic update checking
The system SHALL check for updates automatically on launch when the user has enabled automatic checks. The default value for automatic checks SHALL be enabled. Info.plist SHALL include `SUAutomaticallyChecksForUpdates` set to `true` to explicitly enable this behavior. When a newer version is found, Sparkle SHALL display the standard update dialog prompting the user to install, skip, or be reminded later. If the user chooses to install, Sparkle SHALL download and install the update automatically, then offer to relaunch the app.

#### Scenario: Automatic check finds update
- **WHEN** the app launches with automatic checks enabled and a newer version exists in the appcast
- **THEN** Sparkle displays the update dialog with release notes, offering "Install Update", "Remind Me Later", and "Skip This Version" options

#### Scenario: User accepts automatic update
- **WHEN** the update dialog is shown and the user clicks "Install Update"
- **THEN** Sparkle downloads the update, shows download progress, installs the update, and offers to relaunch the app

#### Scenario: Automatic check disabled
- **WHEN** the app launches with automatic checks disabled
- **THEN** no automatic update check is performed

### Requirement: Manual update check
The system SHALL provide a way for users to manually trigger an update check from both the menu bar ("Check for Updates…") and the Settings UI ("Check for Updates Now"). The manual check flow SHALL behave identically to the automatic check flow when a new version is found — displaying the update dialog and handling download/installation upon user acceptance.

#### Scenario: Manual check finds update
- **WHEN** user triggers a manual update check and a newer version exists
- **THEN** Sparkle displays the update dialog with release notes and install options

#### Scenario: User accepts manual update
- **WHEN** the manual update dialog is shown and the user clicks "Install Update"
- **THEN** Sparkle downloads the update, shows download progress, installs the update, and offers to relaunch the app

#### Scenario: Manual check finds no update
- **WHEN** user triggers a manual update check and the app is up to date
- **THEN** Sparkle displays a "you're up to date" message
