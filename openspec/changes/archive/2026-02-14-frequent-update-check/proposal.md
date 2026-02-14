## Why

The current auto-update check relies on Sparkle's default 24-hour interval, which means users who keep the app open for extended periods may not discover new versions promptly. Checking on every launch and on app focus (with a cooldown) ensures users are notified of updates more quickly.

## What Changes

- Add an `UpdateChecker` class that encapsulates update-checking logic with a 1-hour cooldown
- Trigger an update check immediately on every app launch (bypassing Sparkle's interval throttle)
- Trigger an update check when the app gains focus, subject to the 1-hour cooldown
- Replace direct `SPUStandardUpdaterController` usage in `MangaTranslatorApp` with `UpdateChecker`

## Capabilities

### New Capabilities

_(none — this enhances an existing capability)_

### Modified Capabilities

- `auto-update`: Add proactive update checking on launch and on app focus with a 1-hour cooldown

## Impact

- `MangaTranslator/MangaTranslatorApp.swift` — wire up `UpdateChecker` instead of directly holding the updater controller
- New file: `MangaTranslator/Services/UpdateChecker.swift`
- `MangaTranslator/Views/SettingsView.swift` and `CheckForUpdatesView.swift` — continue receiving `SPUUpdater` from `UpdateChecker`
- No dependency changes (still uses Sparkle 2.x)
