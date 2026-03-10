## Why

The current auto-update logic calls `checkForUpdatesInBackground()` on launch and on app focus, but this method is advisory — Sparkle silently ignores it when its internal scheduler hasn't reached the check interval yet. As a result, automatic checks almost never run in practice, even when the user has enabled them.

## What Changes

- Remove the custom `checkOnLaunch()` call and `startObservingFocus()` observer from `UpdateChecker`
- Remove the `lastCheckDate` cooldown tracking (no longer needed)
- Set `SUScheduledCheckInterval` to `3600` in `Info.plist` so Sparkle's built-in scheduler checks every hour
- Let Sparkle manage all automatic checking via its own reliable internal scheduler

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `auto-update`: The automatic checking requirement is changing — instead of custom launch/focus-triggered `checkForUpdatesInBackground()` calls (which Sparkle ignores), the system will rely entirely on Sparkle's built-in scheduler with a 1-hour interval configured via `SUScheduledCheckInterval`.

## Impact

- `MangaTranslator/Services/UpdateChecker.swift` — simplified, removing launch and focus check logic
- `MangaTranslator/Info.plist` — add `SUScheduledCheckInterval = 3600`
- No API changes, no dependency changes, no UI changes
