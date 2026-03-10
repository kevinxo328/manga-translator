## 1. Tests

- [x] 1.1 Write test: cache hit on repeated retrieve (second call does not invoke SecItemCopyMatching)
- [x] 1.2 Write test: cache miss on first retrieve populates cache and returns value
- [x] 1.3 Write test: retrieve returns nil when neither cache nor Keychain has a value
- [x] 1.4 Write test: retrieve after store returns new value
- [x] 1.5 Write test: retrieve after delete returns nil

## 2. Implementation

- [x] 2.1 Add `private static var cache: [String: String] = [:]` to `KeychainService`
- [x] 2.2 Update `retrieve(for:)` to check cache first, populate cache on Keychain hit
- [x] 2.3 Update `store(_:for:)` to write to cache before Keychain
- [x] 2.4 Update `delete(for:)` to remove from cache before Keychain delete

## 3. Verification

- [x] 3.1 Run all tests and confirm they pass
- [x] 3.2 Build and run the app; confirm Settings page loads existing API keys without Keychain prompt after first access
