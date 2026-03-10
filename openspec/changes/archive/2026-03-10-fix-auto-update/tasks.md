## 1. Info.plist

- [x] 1.1 Add `SUScheduledCheckInterval` key with integer value `3600` to `Info.plist`

## 2. UpdateChecker Simplification

- [x] 2.1 Remove `lastCheckDate` property and `cooldown` constant from `UpdateChecker`
- [x] 2.2 Remove `checkOnLaunch()` method
- [x] 2.3 Remove `startObservingFocus()` method and `appDidBecomeActive()` observer
- [x] 2.4 Remove the `checkOnLaunch()` and `startObservingFocus()` calls from `init()`

## 3. Verification

- [x] 3.1 Build and run the app; confirm no compile errors
- [x] 3.2 Confirm Sparkle initializes correctly (no runtime errors in Console)
- [x] 3.3 Confirm "Check for Updates Now" still works from Settings and menu bar
