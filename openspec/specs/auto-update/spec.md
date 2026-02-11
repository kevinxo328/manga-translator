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
The system SHALL check for updates automatically on launch when the user has enabled automatic checks. The default value for automatic checks SHALL be enabled.

#### Scenario: Automatic check finds update
- **WHEN** the app launches with automatic checks enabled and a newer version exists in the appcast
- **THEN** Sparkle displays the update dialog to the user

#### Scenario: Automatic check disabled
- **WHEN** the app launches with automatic checks disabled
- **THEN** no automatic update check is performed

### Requirement: Manual update check
The system SHALL provide a way for users to manually trigger an update check from the Preferences UI.

#### Scenario: Manual check finds update
- **WHEN** user clicks "Check for Updates Now" and a newer version exists
- **THEN** Sparkle displays the update dialog

#### Scenario: Manual check finds no update
- **WHEN** user clicks "Check for Updates Now" and the app is up to date
- **THEN** Sparkle displays a "you're up to date" message

### Requirement: CI appcast generation
The release CI workflow SHALL generate an `appcast.xml` file containing the version, download URL, file size, and EdDSA signature for the DMG. The appcast SHALL be uploaded as a GitHub Release asset alongside the DMG.

#### Scenario: Tag push triggers appcast generation
- **WHEN** a version tag is pushed and CI builds the DMG
- **THEN** CI signs the DMG with the EdDSA private key, generates `appcast.xml`, and uploads both as release assets
