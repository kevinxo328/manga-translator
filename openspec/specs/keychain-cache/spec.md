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
When `store(_:for:)` is called, the cache SHALL be updated with the new value before the Keychain write completes, so subsequent `retrieve()` calls return the updated value immediately.

#### Scenario: Retrieve after store returns new value
- **WHEN** `store(key, for: engine)` is called followed by `retrieve(for: engine)`
- **THEN** the new key value is returned

### Requirement: Cache consistency on delete
When `delete(for:)` is called, the cache entry for that engine SHALL be removed so subsequent `retrieve()` calls return `nil` without hitting the Keychain.

#### Scenario: Retrieve after delete returns nil
- **WHEN** `delete(for: engine)` is called followed by `retrieve(for: engine)` with no Keychain entry present
- **THEN** `nil` is returned
