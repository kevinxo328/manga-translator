## Purpose

In-memory caching layer for API key retrieval from the system Keychain, reducing redundant Keychain access during a session.

## Requirements

### Requirement: In-memory cache for API key retrieval
`KeychainService` SHALL maintain a static in-memory cache of API keys. On `retrieve()`, the cache SHALL be checked before accessing the Keychain. On a cache hit, the cached value SHALL be returned without a Keychain call.

#### Scenario: Cache hit on repeated retrieve
- **WHEN** `retrieve(for:)` is called for an engine whose key was previously retrieved in the same session
- **THEN** the cached value is returned without invoking `SecItemCopyMatching`

#### Scenario: Cache miss on first retrieve
- **WHEN** `retrieve(for:)` is called for an engine with no cached value
- **THEN** the Keychain is queried, the result is stored in cache, and the value is returned

#### Scenario: Cache miss returns nil for missing key
- **WHEN** `retrieve(for:)` is called and neither cache nor Keychain contains a value for the engine
- **THEN** `nil` is returned and nothing is written to cache

### Requirement: Cache consistency on store
When `store(_:for:)` is called, the implementation SHALL attempt `SecItemUpdate` first (for existing items), falling back to `SecItemAdd` only when the item does not yet exist (`errSecItemNotFound`). The cache SHALL only be updated after the Keychain write succeeds. If the Keychain write fails, both cache and Keychain SHALL remain unchanged, preserving the previous state.

#### Scenario: Retrieve after store returns new value
- **WHEN** `store(key, for: engine)` is called and the Keychain write succeeds (via `SecItemUpdate` or `SecItemAdd`)
- **THEN** the new key value is returned by `retrieve(for: engine)`

#### Scenario: Cache not updated when Keychain write fails
- **WHEN** `store(key, for: engine)` is called and the Keychain write fails
- **THEN** the cache is not updated; any pre-existing Keychain value is preserved

### Requirement: Cache consistency on delete
When `delete(for:)` is called, the implementation SHALL invoke `SecItemDelete` and inspect the result. The cache entry SHALL only be removed if `SecItemDelete` returns `errSecSuccess` or `errSecItemNotFound`. On any other error, both cache and Keychain are left unchanged to preserve consistency.

#### Scenario: Retrieve after successful delete returns nil
- **WHEN** `delete(for: engine)` is called and `SecItemDelete` succeeds
- **THEN** `retrieve(for: engine)` returns `nil`

#### Scenario: Cache preserved when Keychain delete fails
- **WHEN** `delete(for: engine)` is called and `SecItemDelete` returns an error other than `errSecItemNotFound`
- **THEN** the cache entry is not removed, so cache and Keychain remain consistent
