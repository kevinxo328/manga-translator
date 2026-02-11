## Context

MangaTranslator is a native macOS SwiftUI app distributed as a DMG via GitHub Releases. There is no code signing (no Apple Developer account). Users currently have no way to discover new versions without manually checking GitHub.

The CI workflow (`release.yml`) already builds a DMG on tag push and creates a GitHub Release with the DMG attached.

## Goals / Non-Goals

**Goals:**
- Users are notified of new versions and can update in-app
- Update verification via EdDSA (no Apple code signing required)
- User can control whether automatic checks happen
- CI automatically handles signing and appcast generation on release

**Non-Goals:**
- Apple code signing or notarization
- Delta updates (full DMG replacement only)
- Silent/background installation without user confirmation
- Mac App Store distribution

## Decisions

### 1. Update framework: Sparkle 2.x via SPM

**Choice**: Sparkle (https://github.com/sparkle-project/Sparkle)
**Alternatives considered**:
- Custom GitHub API polling: Would require building all UI and verification logic from scratch
- Mac App Store: Requires Apple Developer account and review process

**Rationale**: Sparkle is the de facto standard for non-App Store macOS app updates. Mature, well-maintained, provides complete UI, and supports EdDSA signing without Apple certificates.

### 2. Update verification: EdDSA (Ed25519)

**Choice**: Use Sparkle's built-in EdDSA signing
**Rationale**: Does not require an Apple Developer account. The key pair is generated once — public key goes into Info.plist (`SUPublicEDKey`), private key is stored as a GitHub Actions secret (`SPARKLE_PRIVATE_KEY`) for CI to sign releases.

### 3. Appcast hosting: GitHub Release asset

**Choice**: Upload `appcast.xml` as a release asset alongside the DMG
**Alternatives considered**:
- Repo root (raw URL): Requires CI to push commits back to main, polluting git history
- gh-pages branch: Requires extra branch and GitHub Pages setup

**Rationale**: The `/releases/latest/download/appcast.xml` URL is stable and always points to the latest release. No extra branches, no commits to main, no additional hosting setup.

**Feed URL**: `https://github.com/kevinxo328/manga-translator/releases/latest/download/appcast.xml`

### 4. Sparkle integration pattern

**Choice**: Create `SPUStandardUpdaterController` in `MangaTranslatorApp` and pass it to `SettingsView`
**Rationale**: Sparkle's standard controller manages the entire update lifecycle. The updater instance needs to be shared between the app (for startup checks) and settings (for the manual check button and auto-check toggle).

### 5. Settings UI placement

**Choice**: Add an "Updates" section to the existing Preferences tab in SettingsView
**Rationale**: Keeps all preference-related settings together. Includes a toggle for automatic checks and a button for manual checks.

## Risks / Trade-offs

- **[No code signing]** → macOS Gatekeeper may warn users on first launch. This is the existing situation and not changed by this feature. EdDSA ensures update integrity without Apple signing.
- **[GitHub rate limits]** → The `/releases/latest/download/` URL goes through GitHub's CDN. For a personal project this is not a concern. If it ever becomes one, can migrate appcast to a different host without app changes (just update `SUFeedURL`).
- **[Private key management]** → If the EdDSA private key is lost, a new key pair must be generated and users on old versions won't be able to verify updates from the new key. Mitigation: store the private key securely as a GitHub Actions secret and keep a backup.
