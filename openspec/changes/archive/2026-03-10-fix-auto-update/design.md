## Context

The app uses Sparkle 2 for auto-updates. `UpdateChecker` currently calls `checkForUpdatesInBackground()` on launch and on app-focus events, but this method is advisory — Sparkle silently skips it if its internal scheduling state says it's too early. Sparkle's default check interval is 86400 seconds (24 hours), so the custom launch/focus checks are effectively ignored. Users who enable "Automatically check for updates" see no practical benefit.

## Goals / Non-Goals

**Goals:**
- Auto-update checks actually run reliably when the setting is enabled
- Simplify `UpdateChecker` by removing custom scheduling logic that fought against Sparkle
- Check frequency is 1 hour via Sparkle's built-in scheduler

**Non-Goals:**
- Changing the UI or adding new settings
- Implementing silent/automatic download and install
- Replacing Sparkle with a different update framework

## Decisions

### Use `SUScheduledCheckInterval` instead of custom trigger calls

Sparkle's `checkForUpdatesInBackground()` documents that it may skip the check based on internal state. Rather than fighting this, configure `SUScheduledCheckInterval = 3600` in Info.plist so Sparkle's own reliable internal timer runs every hour. This is the idiomatic Sparkle approach used by most macOS apps.

**Alternative considered**: Call `resetUpdateCycle()` before `checkForUpdatesInBackground()` to force a check. Rejected because `resetUpdateCycle()`'s effect on subsequent background checks is not formally documented, making the behavior fragile.

### Remove `UpdateChecker`'s custom launch and focus logic entirely

Since Sparkle handles scheduling, the `checkOnLaunch()` method and `startObservingFocus()` observer add complexity without benefit. `UpdateChecker` becomes a thin wrapper that initializes `SPUStandardUpdaterController` and exposes the `updater` for UI bindings.

## Risks / Trade-offs

- **Sparkle's first check delay**: On a fresh install, Sparkle may wait up to one full interval before the first automatic check. → Acceptable; users can always use "Check for Updates Now" manually.
- **Less control over exact timing**: We no longer control when checks fire. → Acceptable trade-off for correctness and simplicity.

## Migration Plan

1. Update `Info.plist` with `SUScheduledCheckInterval = 3600`
2. Simplify `UpdateChecker.swift` (remove custom methods)
3. Update the `auto-update` delta spec to reflect new requirement
4. No user-facing changes; no rollback needed
