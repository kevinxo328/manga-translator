## 1. Create UpdateChecker

- [x] 1.1 Create `MangaTranslator/Services/UpdateChecker.swift` as an `ObservableObject` that owns `SPUStandardUpdaterController` and exposes `SPUUpdater`
- [x] 1.2 Implement `checkOnLaunch()` — calls `updater.checkForUpdatesInBackground()` and records `lastCheckDate`
- [x] 1.3 Implement focus observation — observe `NSApplication.didBecomeActiveNotification`, check 1-hour cooldown, call `checkForUpdatesInBackground()` if elapsed
- [x] 1.4 Respect `automaticallyChecksForUpdates` — skip proactive checks when the user has disabled automatic updates

## 2. Wire Up UpdateChecker

- [x] 2.1 Replace `SPUStandardUpdaterController` in `MangaTranslatorApp.swift` with `UpdateChecker`, pass its `updater` to `SettingsView` and menu commands
- [x] 2.2 Verify `CheckForUpdatesView` and `UpdateSettingsView` still receive `SPUUpdater` correctly (no API change needed)

## 3. Verify

- [x] 3.1 Build and run — confirm update check fires on launch
- [x] 3.2 Switch away and back — confirm focus-triggered check fires (or is skipped within cooldown)
