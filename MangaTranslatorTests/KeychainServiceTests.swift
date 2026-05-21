import Testing
import Security
@testable import MangaTranslator

// Tests run serially to prevent static cache interference across cases and suites.
@Suite("KeychainService", .serialized)
struct KeychainServiceTests {

    init() {
        KeychainService.clearCache()
        let service = KeychainService()
        service.delete(for: .openAI)
        service.delete(for: .deepL)
        service.delete(for: .google)
    }

    // MARK: - 1.1 Cache hit on repeated retrieve

    @Test("Repeated retrieve returns cached value without re-reading Keychain")
    func cacheHitOnRepeatedRetrieve() {
        var service = KeychainService()
        service.secItemAdd = { _, _ in errSecSuccess }
        service.store("key-openai", for: .openAI)

        let first = service.retrieve(for: .openAI)
        #expect(first == "key-openai")

        // Simulate Keychain miss; cache must still serve the value.
        service.secItemCopyMatching = { _, _ in errSecItemNotFound }
        let second = service.retrieve(for: .openAI)
        #expect(second == "key-openai")
    }

    // MARK: - 1.2 Cache miss on first retrieve populates cache

    @Test("Cache miss: first retrieve reads Keychain and populates cache")
    func cacheMissPopulatesCache() {
        let service = KeychainService()
        KeychainService.writeToKeychainOnly("direct-key", for: .deepL)

        let value = service.retrieve(for: .deepL)
        #expect(value == "direct-key")

        KeychainService.evictFromKeychainOnly(for: .deepL)
        #expect(service.retrieve(for: .deepL) == "direct-key")
    }

    // MARK: - 1.3 Retrieve returns nil for missing key

    @Test("Retrieve returns nil when neither cache nor Keychain has a value")
    func retrieveReturnsNilForMissingKey() {
        let service = KeychainService()
        #expect(service.retrieve(for: .google) == nil)
    }

    // MARK: - 1.4 Retrieve after store returns new value

    @Test("Retrieve after store returns updated value")
    func retrieveAfterStoreReturnsNewValue() {
        var service = KeychainService()
        service.secItemAdd = { _, _ in errSecSuccess }

        service.store("first", for: .openAI)
        #expect(service.retrieve(for: .openAI) == "first")

        service.store("second", for: .openAI)
        #expect(service.retrieve(for: .openAI) == "second")
    }

    // MARK: - 1.5 Retrieve after delete returns nil

    @Test("Retrieve after delete returns nil")
    func retrieveAfterDeleteReturnsNil() {
        var service = KeychainService()
        service.secItemAdd = { _, _ in errSecSuccess }

        service.store("to-delete", for: .deepL)
        #expect(service.retrieve(for: .deepL) == "to-delete")

        service.delete(for: .deepL)
        #expect(service.retrieve(for: .deepL) == nil)
    }

    // MARK: - Status handling

    @Test("Cache is not updated when SecItemAdd fails")
    func cacheNotUpdatedOnSecItemAddFailure() {
        var service = KeychainService()
        service.secItemAdd = { _, _ in errSecNotAvailable }

        service.store("should-not-cache", for: .openAI)

        #expect(service.retrieve(for: .openAI) == nil,
                "Cache must not be populated when SecItemAdd fails")
    }

    @Test("Cache is updated when SecItemAdd succeeds")
    func cacheUpdatedOnSecItemAddSuccess() {
        var service = KeychainService()
        service.secItemAdd = { _, _ in errSecSuccess }

        service.store("valid-key", for: .openAI)

        #expect(service.retrieve(for: .openAI) == "valid-key",
                "Cache must be populated after a successful SecItemAdd")
    }

    @Test("retrieve returns nil on errSecItemNotFound without writing to cache")
    func retrieveReturnsNilOnItemNotFound() {
        var service = KeychainService()
        service.secItemCopyMatching = { _, _ in errSecItemNotFound }

        #expect(service.retrieve(for: .deepL) == nil)
    }

    @Test("retrieve returns nil on unexpected Keychain error without polluting cache")
    func retrieveReturnsNilOnUnexpectedError() {
        var service = KeychainService()
        service.secItemCopyMatching = { _, _ in errSecInteractionNotAllowed }

        #expect(service.retrieve(for: .deepL) == nil,
                "Unexpected Keychain error must return nil without writing to cache")

        service.secItemCopyMatching = nil
        #expect(service.retrieve(for: .deepL) == nil)
    }

    // MARK: - Update + Add pattern

    @Test("Existing Keychain value is not lost when store update fails")
    func existingKeyPreservedOnStoreFailure() {
        KeychainService.writeToKeychainOnly("original-key", for: .openAI)

        var service = KeychainService()
        service.secItemUpdate = { _, _ in errSecNotAvailable }
        service.secItemAdd = { _, _ in errSecNotAvailable }
        service.store("new-key", for: .openAI)

        let keychain = KeychainService.readFromKeychainOnly(for: .openAI)
        #expect(keychain == "original-key",
                "Original Keychain value must survive a failed store attempt")
    }

    @Test("store uses SecItemUpdate for existing key, not delete-then-add")
    func storeUpdatesExistingKeyWithoutDelete() {
        KeychainService.writeToKeychainOnly("original-key", for: .openAI)

        var updateCalled = false
        var service = KeychainService()
        service.secItemUpdate = { _, _ in updateCalled = true; return errSecSuccess }
        service.store("new-key", for: .openAI)

        #expect(updateCalled, "store must call SecItemUpdate when item already exists")
        #expect(service.retrieve(for: .openAI) == "new-key")
    }

    // MARK: - delete status handling

    @Test("Cache is not cleared when Keychain delete fails")
    func cachePreservedOnDeleteFailure() {
        var service = KeychainService()
        service.secItemAdd = { _, _ in errSecSuccess }
        service.store("key-to-keep", for: .openAI)

        service.secItemDelete = { _ in errSecInteractionNotAllowed }
        service.delete(for: .openAI)

        #expect(service.retrieve(for: .openAI) == "key-to-keep",
                "Cache must be preserved when Keychain delete fails to maintain consistency")
    }

    // MARK: - Bounded concurrent cache access

    @Test("Bounded concurrent retrieve/store/delete does not race")
    func boundedConcurrentRetrieveStoreDeleteDoesNotRace() async {
        let engines: [TranslationEngine] = [.openAI, .deepL, .google]
        let operations = (0..<60).flatMap { index in
            engines.map { engine in (engine, "bounded-\(engine.rawValue)-\(index)") }
        }

        for batchStart in stride(from: operations.startIndex, to: operations.endIndex, by: 3) {
            let batchEnd = min(batchStart + 3, operations.endIndex)
            await withTaskGroup(of: Void.self) { group in
                for operation in operations[batchStart..<batchEnd] {
                    group.addTask {
                        var service = KeychainService()
                        service.secItemAdd = { _, _ in errSecSuccess }
                        service.secItemUpdate = { _, _ in errSecSuccess }
                        service.secItemDelete = { _ in errSecSuccess }
                        service.secItemCopyMatching = { _, _ in errSecItemNotFound }

                        service.store(operation.1, for: operation.0)
                        #expect(service.retrieve(for: operation.0) == operation.1)
                        #expect(service.hasKey(for: operation.0))
                        service.delete(for: operation.0)
                    }
                }
            }
        }

        for engine in engines {
            let finalValue = "final-\(engine.rawValue)"
            var service = KeychainService()
            service.secItemAdd = { _, _ in errSecSuccess }
            service.secItemUpdate = { _, _ in errSecSuccess }

            service.store(finalValue, for: engine)
            #expect(service.retrieve(for: engine) == finalValue,
                    "Final deterministic store must win after bounded concurrent cache access")
        }
    }
}
