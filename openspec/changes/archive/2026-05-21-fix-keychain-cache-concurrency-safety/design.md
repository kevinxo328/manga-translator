## Context

`KeychainService` is a small synchronous value type used by `SettingsView`, `TranslationViewModel`, and the translation services. It stores API keys in macOS Keychain and keeps a process-wide static `[String: String]` cache to avoid repeated Keychain reads after the first access.

The app has two relevant access patterns:

- Settings access is low-frequency and user-driven: load all keys on appear, store a key when a secure field changes, and delete a key when the field is emptied.
- Translation access is bounded async work: the batch pipeline starts at most three page tasks concurrently, and those tasks can call `hasKey(for:)` or provider `retrieve(for:)` before API requests.

The unsafe part is not Keychain throughput. The unsafe part is direct concurrent access to the static Swift `Dictionary` at `KeychainService.cache`.

## Goals / Non-Goals

**Goals:**

- Make every read and write of `KeychainService.cache` memory-safe under the app's bounded async task pipeline.
- Preserve the existing synchronous `KeychainService` API and all current call sites.
- Preserve the existing cache consistency contract for successful and failed Keychain operations.
- Keep the implementation small and local to `KeychainService`.
- Add a regression test that exercises the production-like bounded concurrency shape.

**Non-Goals:**

- Do not convert `KeychainService` to an actor or async API.
- Do not serialize the full Keychain operation lifecycle. This change guarantees synchronized dictionary access, not transaction ordering between concurrent settings writes and translation reads.
- Do not add cache expiration, encryption of in-memory values, or a new credential storage abstraction.
- Do not change provider API-key retrieval behavior outside the cache safety boundary.
- Do not add logs or error messages that include API-key values.

## Decisions

### D1. Keep the public API synchronous

Keep `store(_:for:)`, `retrieve(for:)`, `delete(for:)`, `hasKey(for:)`, and `clearCache()` synchronous.

Rationale: Existing call sites use `KeychainService` from SwiftUI event handlers, `@MainActor` view-model code, and translation service methods without awaiting. Changing the service to an actor would force unrelated call-site churn and expand this task beyond cache safety.

Alternative considered: an `actor KeychainCache`. Rejected because it would require async access or detached bridging for a problem that only needs a local memory-safety guard.

### D2. Protect only the static cache dictionary with a small lock boundary

Introduce a private static `NSLock` in `KeychainService` and route all static cache access through helper methods. The protected operations are:

- cache lookup by account
- cache set by account
- cache remove by account
- cache clear

Rationale: This directly addresses the race on Swift `Dictionary` without changing Keychain behavior. Keychain calls remain outside the lock, so the lock does not serialize potentially slow Security framework operations.

Alternative considered: wrapping entire `store`, `retrieve`, and `delete` methods in one lock. Rejected because it would unnecessarily hold the lock during Keychain calls and could increase UI stalls without improving dictionary safety.

### D3. Preserve existing failure semantics

The implementation must keep these rules:

- `store(_:for:)` updates cache only after `SecItemUpdate` or `SecItemAdd` returns `errSecSuccess`.
- `store(_:for:)` does not write an empty cache entry; invalid UTF-8 conversion still exits without mutation.
- `delete(for:)` removes cache only after `SecItemDelete` returns `errSecSuccess` or `errSecItemNotFound`.
- `retrieve(for:)` writes cache only after `SecItemCopyMatching` returns valid UTF-8 data.
- `clearCache()` clears all cache entries.

Rationale: Existing tests and `openspec/specs/keychain-cache/spec.md` already define these consistency rules. This change must not weaken them while adding synchronization.

### D4. Test bounded concurrency with Thread Sanitizer, not high-throughput Keychain load

Add one regression test that uses `withTaskGroup` with a maximum of three concurrent operations over `.openAI`, `.deepL`, and `.google`, then performs deterministic final operations and verifies final state. Run the new test with Thread Sanitizer enabled to make the pre-fix data race observable instead of relying on an intermittent crash.

Rationale: This matches the app's translation pipeline concurrency limit and avoids encoding a false requirement that the service is optimized for unbounded or high-volume concurrent Keychain traffic.

## Risks / Trade-offs

- Risk: A race between a cache miss and a later store can still allow an older Keychain value to be loaded after a concurrent write. Mitigation: the production usage does not intentionally write settings keys during active translation, and this change is scoped to dictionary memory safety rather than cross-operation transaction ordering.
- Risk: Locking only dictionary operations means Thread Sanitizer may still report races if future code adds new unsynchronized static state. Mitigation: all current static mutable cache access must go through the new locked helpers.
- Risk: The concurrency test proves the bounded app-shaped path, not all possible interleavings. Mitigation: run the bounded test with Thread Sanitizer and keep focused synchronization around every dictionary access.
