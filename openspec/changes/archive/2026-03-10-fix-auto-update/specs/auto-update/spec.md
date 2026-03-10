## MODIFIED Requirements

### Requirement: Automatic update checking
The system SHALL check for updates automatically using Sparkle's built-in scheduler. The check interval SHALL be configured to 3600 seconds via `SUScheduledCheckInterval` in `Info.plist`. The default value for automatic checks SHALL be enabled (`SUAutomaticallyChecksForUpdates = true`). The system SHALL NOT implement custom launch-triggered or focus-triggered `checkForUpdatesInBackground()` calls — all scheduling is delegated entirely to Sparkle's internal timer. When a newer version is found, Sparkle SHALL display the standard update dialog prompting the user to install, skip, or be reminded later. If the user chooses to install, Sparkle SHALL download and install the update automatically, then offer to relaunch the app.

#### Scenario: Sparkle scheduler triggers check
- **WHEN** the app is running and Sparkle's internal 1-hour timer fires with automatic checks enabled
- **THEN** Sparkle performs a background update check and shows the update dialog if a newer version is found

#### Scenario: Automatic check finds update
- **WHEN** Sparkle's scheduled check finds a newer version in the appcast
- **THEN** Sparkle displays the update dialog with release notes, offering "Install Update", "Remind Me Later", and "Skip This Version" options

#### Scenario: User accepts automatic update
- **WHEN** the update dialog is shown and the user clicks "Install Update"
- **THEN** Sparkle downloads the update, shows download progress, installs the update, and offers to relaunch the app

#### Scenario: Automatic check disabled
- **WHEN** the app is running with automatic checks disabled
- **THEN** no automatic update check is performed by Sparkle's scheduler
