## 1. Test First

- [x] 1.1 Add `boundedConcurrentRetrieveStoreDeleteDoesNotRace` to `MangaTranslatorTests/KeychainServiceTests.swift`.
- [x] 1.2 In the new test, use `withTaskGroup` with no more than three concurrent operations at a time to mirror the production batch pipeline limit.
- [x] 1.3 In the new test, exercise `.openAI`, `.deepL`, and `.google` with successful store, retrieve, has-key, and delete operations.
- [x] 1.4 In the new test, after bounded concurrent operations complete, perform deterministic final successful `store(_:for:)` calls and assert each subsequent `retrieve(for:)` returns the final value.
- [x] 1.5 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/KeychainServiceTests -enableThreadSanitizer YES` and confirm Thread Sanitizer reports the pre-fix cache data race.

## 2. Cache Synchronization Implementation

- [x] 2.1 In `MangaTranslator/Services/KeychainService.swift`, add a private static `NSLock` for cache access.
- [x] 2.2 Add private static helper methods for cache lookup, cache set, cache removal, and cache clear; every helper must acquire the synchronization primitive.
- [x] 2.3 Replace all direct `Self.cache[...]`, `Self.cache.removeValue`, and `cache = [:]` access with the synchronized helper methods.
- [x] 2.4 Keep Security framework calls outside the cache lock.
- [x] 2.5 Preserve the existing synchronous public API; do not add async methods, actors, public locks, or public cache abstractions.

## 3. Consistency Preservation

- [x] 3.1 Confirm `store(_:for:)` updates the cache only after `SecItemUpdate` or `SecItemAdd` returns `errSecSuccess`.
- [x] 3.2 Confirm `retrieve(for:)` writes to cache only after `SecItemCopyMatching` returns valid UTF-8 data.
- [x] 3.3 Confirm `delete(for:)` removes from cache only after `SecItemDelete` returns `errSecSuccess` or `errSecItemNotFound`.
- [x] 3.4 Confirm `clearCache()` clears all provider cache entries through the synchronized cache-clear helper.
- [x] 3.5 Confirm no log message, thrown error, or test failure message includes an API-key value.

## 4. Verification

- [x] 4.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/KeychainServiceTests` and confirm all KeychainService tests pass.
- [x] 4.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/KeychainServiceTests -enableThreadSanitizer YES` and confirm Thread Sanitizer does not report cache data races.
- [x] 4.3 Run `openspec validate fix-keychain-cache-concurrency-safety --strict` and confirm the change is valid.
- [x] 4.4 Update `PLAN.md` task 5 status only after the tests and strict OpenSpec validation pass.
