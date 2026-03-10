## Why

Every time the app is rebuilt or updated, macOS requires re-authorization to access Keychain items due to code signing changes. Adding an in-memory cache layer reduces Keychain access frequency, improving the experience for both developers and end users.

## What Changes

- Add a static in-memory cache to `KeychainService` so Keychain is accessed at most once per session per engine
- `retrieve()` checks cache first; on cache miss, reads from Keychain and stores the result in cache
- `store()` updates both cache and Keychain
- `delete()` clears both cache and Keychain

## Capabilities

### New Capabilities

- `keychain-cache`: In-memory cache layer on top of KeychainService to reduce repeated Keychain access within a session

### Modified Capabilities

- `settings-management`: API key retrieval behavior gains a cache layer (requirements unchanged, implementation enhancement only)

## Impact

- `MangaTranslator/Services/KeychainService.swift`: add static cache dictionary and related logic
- No interface or behavioral changes to callers (`TranslationViewModel`, `SettingsView`, translation services)
- No external dependency changes
