## MODIFIED Requirements

### Requirement: Automatic update checking
The system SHALL check for updates automatically on launch when the user has enabled automatic checks. The default value for automatic checks SHALL be enabled. Info.plist SHALL include `SUAutomaticallyChecksForUpdates` set to `true` to explicitly enable this behavior. On every app launch, the system SHALL call `checkForUpdatesInBackground()` to perform an immediate check regardless of Sparkle's internal interval throttle. Additionally, the system SHALL check for updates when the app gains focus (`NSApplication.didBecomeActiveNotification`), subject to a 1-hour cooldown — if less than 1 hour has elapsed since the last proactive check, the focus-triggered check SHALL be skipped. When a newer version is found, Sparkle SHALL display the standard update dialog prompting the user to install, skip, or be reminded later. If the user chooses to install, Sparkle SHALL download and install the update automatically, then offer to relaunch the app.

#### Scenario: Launch check runs immediately
- **WHEN** the app launches with automatic checks enabled
- **THEN** the system performs a background update check immediately, regardless of when the last check occurred

#### Scenario: Focus check within cooldown
- **WHEN** the app gains focus and the last proactive check was less than 1 hour ago
- **THEN** no update check is performed

#### Scenario: Focus check after cooldown
- **WHEN** the app gains focus and the last proactive check was more than 1 hour ago (or no check has been performed yet in this session)
- **THEN** the system performs a background update check

#### Scenario: Automatic check finds update
- **WHEN** a background check finds a newer version in the appcast
- **THEN** Sparkle displays the update dialog with release notes, offering "Install Update", "Remind Me Later", and "Skip This Version" options

#### Scenario: User accepts automatic update
- **WHEN** the update dialog is shown and the user clicks "Install Update"
- **THEN** Sparkle downloads the update, shows download progress, installs the update, and offers to relaunch the app

#### Scenario: Automatic check disabled
- **WHEN** the app launches with automatic checks disabled
- **THEN** no automatic or focus-triggered update check is performed
