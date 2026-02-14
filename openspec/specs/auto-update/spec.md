## Purpose

Sparkle-based automatic update checking and in-app update installation.

## Requirements

### Requirement: Sparkle framework integration
The system SHALL integrate Sparkle 2.x as a Swift Package dependency and initialize `SPUStandardUpdaterController` at app launch to manage the update lifecycle.

#### Scenario: App launches with Sparkle initialized
- **WHEN** the app starts
- **THEN** Sparkle's updater controller is initialized and ready to check for updates

### Requirement: EdDSA update verification
The system SHALL embed the EdDSA public key in Info.plist (`SUPublicEDKey`) and configure the feed URL (`SUFeedURL`) pointing to `https://github.com/kevinxo328/manga-translator/releases/latest/download/appcast.xml`. Sparkle SHALL verify downloaded updates against the EdDSA signature before installation.

#### Scenario: Valid update signature
- **WHEN** Sparkle downloads a new DMG and the EdDSA signature matches the embedded public key
- **THEN** the update proceeds to installation

#### Scenario: Invalid update signature
- **WHEN** Sparkle downloads a new DMG and the EdDSA signature does not match
- **THEN** the update is rejected and the user is notified

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

### Requirement: CI appcast generation
The release CI workflow SHALL generate an `appcast.xml` file containing the version, download URL, file size, and EdDSA signature for the DMG. The appcast SHALL be uploaded as a GitHub Release asset alongside the DMG.

#### Scenario: Tag push triggers appcast generation
- **WHEN** a version tag is pushed and CI builds the DMG
- **THEN** CI signs the DMG with the EdDSA private key, generates `appcast.xml`, and uploads both as release assets
