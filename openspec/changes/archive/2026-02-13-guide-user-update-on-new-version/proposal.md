## Why

When the app detects a new version (via automatic or manual check), it should proactively prompt the user to update and handle the download/installation seamlessly. Currently, the Sparkle integration initializes the updater and provides a manual check button, but the user experience around update discovery and installation guidance may not be clear or consistent across both check modes.

## What Changes

- Configure Sparkle's user interaction delegate to ensure the update alert is always presented when a new version is found (both automatic and manual checks)
- Ensure the update dialog clearly prompts the user to install, and if accepted, Sparkle downloads and installs the update automatically
- Verify that `SPUStandardUpdaterController` is properly configured so the standard Sparkle UI flow (alert → download → install → relaunch) works end-to-end
- Review and fix any delegate or configuration issues that may prevent the update prompt from appearing

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `auto-update`: Ensure the update flow properly guides users through installation when a new version is detected — the update alert must appear for both automatic and manual checks, and selecting "Install" must download and install the update seamlessly

## Impact

- `MangaTranslator/MangaTranslatorApp.swift` — SPUStandardUpdaterController initialization and delegate configuration
- `MangaTranslator/Views/CheckForUpdatesView.swift` — Manual update check trigger
- `MangaTranslator/Views/SettingsView.swift` — Update settings UI and manual check button
- Sparkle framework configuration (Info.plist keys: `SUFeedURL`, `SUPublicEDKey`, `SUAutomaticallyUpdate`)
