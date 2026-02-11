## Why

Users currently have no way to know when a new version of MangaTranslator is available. They must manually check GitHub Releases to discover and download updates. Adding automatic update checking improves the user experience and ensures users benefit from bug fixes and new features promptly.

## What Changes

- Integrate the Sparkle framework (via SPM) to provide automatic update checking and in-app update installation
- Use EdDSA (Ed25519) signing for update verification (no Apple Developer certificate required)
- Host `appcast.xml` as a GitHub Release asset so Sparkle can discover new versions
- Add a toggle in Preferences to enable/disable automatic update checks
- Add a "Check for Updates Now" button in Preferences for manual checks
- Update the CI release workflow to generate EdDSA signatures and publish `appcast.xml` alongside the DMG

## Capabilities

### New Capabilities
- `auto-update`: Sparkle-based automatic update checking, user preferences for update behavior, and manual update check trigger

### Modified Capabilities
- `settings-management`: Add update preferences section (auto-check toggle, manual check button)

## Impact

- **Dependencies**: Adds Sparkle 2.x as a Swift Package dependency
- **Build**: Requires EdDSA key pair generation; public key embedded in Info.plist, private key stored as GitHub Actions secret
- **CI**: `release.yml` gains steps for signing DMG with EdDSA and generating/uploading `appcast.xml`
- **App entry point**: `MangaTranslatorApp.swift` initializes Sparkle's `SPUStandardUpdaterController`
- **Settings UI**: `SettingsView.swift` Preferences tab gains an "Updates" section
- **Info.plist**: New keys `SUFeedURL`, `SUPublicEDKey`
