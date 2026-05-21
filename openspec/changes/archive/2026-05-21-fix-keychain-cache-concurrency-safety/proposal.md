## Why

`KeychainService` keeps a process-wide static dictionary of plaintext API keys, but the dictionary is read and written without synchronization. The app does not use Keychain at high scale, but the batch translation pipeline can run up to three async tasks that check or retrieve API keys concurrently, which is enough to make unsynchronized Swift `Dictionary` access unsafe.

## What Changes

- Protect every read and write of the static Keychain memory cache with a private static `NSLock`.
- Preserve the existing synchronous `KeychainService` public API: `store(_:for:)`, `retrieve(for:)`, `delete(for:)`, `hasKey(for:)`, and `clearCache()`.
- Preserve existing cache consistency rules: cache updates happen only after successful Keychain writes, cache eviction happens only after successful or not-found Keychain deletes, and failed Keychain operations do not split cache state from Keychain state.
- Add a bounded concurrency regression test that matches the production batch pipeline shape instead of treating Keychain as a high-throughput concurrent subsystem.
- Do not add API-key logging, error descriptions containing API keys, cache expiration, or async actor-based APIs in this change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keychain-cache`: Add a concurrency-safety requirement for the existing static in-memory API-key cache under the app's bounded async translation pipeline.

## Impact

- Affected implementation: `MangaTranslator/Services/KeychainService.swift`.
- Affected tests: `MangaTranslatorTests/KeychainServiceTests.swift`.
- Public API impact: none; call sites remain synchronous.
- Dependency impact: none; use `NSLock` from Foundation.
