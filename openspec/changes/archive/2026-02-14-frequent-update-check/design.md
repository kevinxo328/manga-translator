## Context

The app currently relies on Sparkle's default 24-hour `updateCheckInterval`. The updater is initialized in `MangaTranslatorApp` with `startingUpdater: true` and no delegate customization. Settings and menu bar provide manual check buttons that call `SPUUpdater.checkForUpdates()`.

## Goals / Non-Goals

**Goals:**
- Check for updates on every app launch, bypassing Sparkle's interval throttle
- Check for updates when the app gains focus, with a 1-hour cooldown to avoid excessive requests
- Encapsulate update-checking logic in a dedicated `UpdateChecker` class

**Non-Goals:**
- Changing the Sparkle framework or its configuration (feed URL, signing keys)
- Auto-downloading or silently installing updates
- Adding user-configurable cooldown duration (hardcoded to 1 hour)

## Decisions

### 1. Dedicated `UpdateChecker` class

**Decision**: Create `UpdateChecker` as an `ObservableObject` that owns the `SPUStandardUpdaterController` and exposes the `SPUUpdater` for views.

**Rationale**: Keeps update logic out of the app entry point. Views (`SettingsView`, `CheckForUpdatesView`) continue to receive `SPUUpdater` — no changes needed to view code beyond passing a different source.

**Alternative considered**: Adding logic directly in `MangaTranslatorApp` with `onReceive`. Rejected because it mixes concerns and is harder to test.

### 2. Use `checkForUpdatesInBackground()` for proactive checks

**Decision**: Use `SPUUpdater.checkForUpdatesInBackground()` instead of `checkForUpdates()`.

**Rationale**: `checkForUpdatesInBackground()` is non-interactive — it only shows UI if an update is found. `checkForUpdates()` always shows UI (including "you're up to date"), which would be disruptive on every focus event.

### 3. In-memory cooldown tracking

**Decision**: Track last check time as an in-memory `Date?` property. No persistence to UserDefaults.

**Rationale**: On app restart, the launch check runs anyway, so there's no value in persisting the timestamp across sessions. Simpler implementation.

### 4. Observe `NSApplication.didBecomeActiveNotification` for focus

**Decision**: Use `NotificationCenter` to observe `didBecomeActiveNotification`.

**Rationale**: This fires when the app becomes the frontmost app (e.g., user clicks on it from another app or switches via Cmd-Tab). It does NOT fire for window-level focus changes within the app, which is the desired granularity.

## Risks / Trade-offs

- **GitHub rate limiting** → The appcast.xml is a small static file served from GitHub Releases CDN. With a 1-hour cooldown, a single user generates at most ~16 requests/day. No concern.
- **Startup delay** → `checkForUpdatesInBackground()` runs asynchronously and does not block the main thread. No UI impact.
- **Notification observer lifecycle** → The observer is tied to `UpdateChecker`'s lifetime, which is owned by `MangaTranslatorApp` (app-scoped). No risk of premature deallocation.
