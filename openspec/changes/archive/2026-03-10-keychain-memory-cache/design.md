## Context

`KeychainService` is a struct used across `TranslationViewModel`, `SettingsView`, and three translation services (`OpenAITranslationService`, `DeepLTranslationService`, `GoogleTranslationService`). Currently every `retrieve()` call goes directly to the macOS Keychain via `SecItemCopyMatching`. Because the app uses ad-hoc code signing, macOS re-prompts for Keychain authorization on each new binary (every rebuild or app update), degrading both the developer workflow and the end-user upgrade experience.

## Goals / Non-Goals

**Goals:**
- Reduce Keychain system calls to at most one per engine per app session
- Ensure cache stays consistent with Keychain on every `store()` and `delete()`
- Zero interface changes to any caller

**Non-Goals:**
- Persisting the cache across app launches (cache is session-only by design)
- Encrypting or obfuscating keys in memory
- Replacing Keychain as the durable storage backend

## Decisions

### Static cache dictionary on the struct

`KeychainService` is a struct (value type). A `private static var cache: [String: String] = [:]` is shared across all instances without requiring callers to hold a reference to a single shared object. This avoids refactoring the entire call graph to pass a singleton.

**Alternatives considered:**
- Convert to `class` with shared singleton — would require changes in all five call sites and the dependency injection pattern in translation services.
- Use `@StateObject` / `@EnvironmentObject` — SwiftUI-specific and not appropriate for a plain service struct.

### Cache key = `engine.rawValue`

The existing Keychain account name is already `engine.rawValue`. Reusing the same key keeps the two stores symmetric and avoids a separate mapping.

### Write-through on `store()` and `delete()`

Both operations update cache and Keychain atomically (cache first, then Keychain). This ensures that a `retrieve()` immediately after `store()` always returns the new value, and a `retrieve()` after `delete()` always returns `nil`.

## Risks / Trade-offs

- **Stale cache if Keychain is modified externally** (e.g., user edits key via Keychain Access.app) → Mitigation: acceptable for this use case; the app is the sole writer of these items.
- **Memory footprint** → Negligible; API keys are short strings, at most three entries.

## Migration Plan

No data migration needed. The cache starts empty on every launch and populates lazily on first `retrieve()`. Existing Keychain items are unaffected.
