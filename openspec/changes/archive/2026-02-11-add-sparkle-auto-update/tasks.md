## 1. Setup

- [x] 1.1 Add Sparkle 2.x as a Swift Package dependency in the Xcode project
- [x] 1.2 Generate EdDSA key pair using Sparkle's `generate_keys` tool
- [x] 1.3 Add `SUFeedURL` and `SUPublicEDKey` to Info.plist

## 2. App Integration

- [x] 2.1 Initialize `SPUStandardUpdaterController` in `MangaTranslatorApp.swift` and pass it to SettingsView
- [x] 2.2 Add "Updates" section to the Preferences tab in `SettingsView.swift` with auto-check toggle and manual check button

## 3. CI / Release Pipeline

- [x] 3.1 Create `scripts/generate_appcast.sh` to produce `appcast.xml` from version, download URL, file size, and EdDSA signature
- [x] 3.2 Update `release.yml` to download Sparkle CLI tools, sign the DMG with EdDSA, generate appcast.xml, and upload it as a release asset
- [x] 3.3 Add `SPARKLE_PRIVATE_KEY` as a GitHub Actions secret (manual step, documented)
