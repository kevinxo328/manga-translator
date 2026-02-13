## 1. Info.plist Configuration

- [x] 1.1 Add `SUAutomaticallyChecksForUpdates` key set to `true` in `MangaTranslator/Info.plist`

## 2. Fix Version Mismatch (Root Cause)

- [x] 2.1 Fix `generate_appcast.sh` to strip "v" prefix from tag version so `sparkle:version` and `sparkle:shortVersionString` match `CFBundleVersion` and `CFBundleShortVersionString`
- [x] 2.2 Fix `build_dmg.sh` to strip "v" prefix from `VERSION` env var and pass `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to xcodebuild so the app bundle has the correct version

## 3. Verification

- [x] 3.1 Verify `SPUStandardUpdaterController` initialization in `MangaTranslatorApp.swift` uses `startingUpdater: true`
- [x] 3.2 Verify the `SUFeedURL` in Info.plist points to a valid, accessible appcast.xml URL
- [x] 3.3 Build and run the app, confirm the Sparkle update dialog appears when a newer version exists in the appcast (automatic check on launch)
- [x] 3.4 Trigger manual update check from menu bar "Check for Updates…" and from Settings "Check for Updates Now", confirm the update dialog appears
- [x] 3.5 Accept an update in the dialog and confirm download, installation, and relaunch prompt work end-to-end
