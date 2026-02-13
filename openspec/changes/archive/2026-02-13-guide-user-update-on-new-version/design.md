## Context

The app uses Sparkle 2.x via `SPUStandardUpdaterController` initialized with `startingUpdater: true` in `MangaTranslatorApp.swift`. The current configuration:

- `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` — uses Sparkle's default standard UI
- Info.plist has `SUFeedURL` and `SUPublicEDKey` but no `SUAutomaticallyChecksForUpdates` or `SUAutomaticallyUpdate` keys
- SettingsView provides a toggle for `automaticallyChecksForUpdates` and a manual "Check for Updates Now" button
- Menu bar has a "Check for Updates…" item via `CheckForUpdatesView`

The current setup relies entirely on Sparkle's default behavior. When a new version is found, Sparkle's standard alert should appear — but without explicit configuration of `SUAutomaticallyChecksForUpdates` in Info.plist, the default behavior may not consistently prompt users.

## Goals / Non-Goals

**Goals:**
- Ensure the Sparkle update alert reliably appears when a new version is detected (both automatic and manual checks)
- When user accepts, Sparkle downloads and installs the update seamlessly
- Add `SUAutomaticallyChecksForUpdates` to Info.plist to explicitly enable automatic checks by default
- Verify the end-to-end flow: detection → prompt → download → install → relaunch

**Non-Goals:**
- Building a custom update UI (Sparkle's standard UI is sufficient)
- Silent/forced updates without user consent
- In-app notification banners or badges for available updates

## Decisions

### Decision 1: Add `SUAutomaticallyChecksForUpdates` to Info.plist

Set `SUAutomaticallyChecksForUpdates` to `true` in Info.plist to explicitly enable automatic update checking on launch. While Sparkle defaults to checking automatically, making this explicit ensures consistent behavior and makes the intent clear.

**Alternative considered**: Rely on Sparkle's implicit default — rejected because explicit configuration is more reliable and easier to audit.

### Decision 2: Keep `SPUStandardUpdaterController` with default UI driver

Continue using `SPUStandardUpdaterController` with `userDriverDelegate: nil`, which provides Sparkle's built-in update alert (release notes, "Install Update" / "Remind Me Later" / "Skip This Version" buttons). This standard flow already handles:
- Showing the update prompt with release notes
- Downloading the update with progress
- Installing and relaunching the app

**Alternative considered**: Custom `SPUUserDriver` implementation — rejected because the standard UI already provides the exact flow the user needs (prompt → download → install) and is well-tested.

### Decision 3: Verify appcast.xml accessibility and format

The update flow depends on `appcast.xml` being correctly generated and accessible at the configured `SUFeedURL`. Need to verify that:
- The appcast URL resolves correctly
- The appcast contains proper version information and EdDSA signatures
- The DMG download URL in the appcast is accessible

This is a verification step, not a code change.

## Risks / Trade-offs

- **[Appcast not found or malformed]** → Sparkle silently fails if the appcast URL returns 404 or invalid XML. Mitigation: Verify the appcast URL is correct and CI generates valid appcast files. Consider adding `SPUUpdaterDelegate` methods to log update check failures for debugging.
- **[macOS Gatekeeper blocking unsigned DMG]** → If the DMG is not notarized, macOS may block installation. Mitigation: This is handled by CI signing; verify the release workflow includes proper signing.
- **[User confusion with Sparkle's standard UI language]** → Sparkle's default UI is in English. Mitigation: Sparkle supports localization, but this is a non-goal for this change.
