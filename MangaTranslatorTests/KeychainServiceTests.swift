import Testing
@testable import MangaTranslator

// Tests run serially to avoid static cache interference between cases.
@Suite("KeychainService Cache", .serialized)
struct KeychainServiceCacheTests {

    init() {
        KeychainService.clearCache()
        // Clean up any Keychain residue from previous runs.
        let service = KeychainService()
        service.delete(for: .openAI)
        service.delete(for: .deepL)
        service.delete(for: .google)
    }

    // MARK: - 1.1 Cache hit on repeated retrieve

    @Test("Repeated retrieve returns cached value without re-reading Keychain")
    func cacheHitOnRepeatedRetrieve() {
        let service = KeychainService()
        service.store("key-openai", for: .openAI)

        // First retrieve populates cache (value already there via store).
        let first = service.retrieve(for: .openAI)
        #expect(first == "key-openai")

        // Evict from Keychain directly so only the cache holds the value.
        KeychainService.evictFromKeychainOnly(for: .openAI)

        // Second retrieve must still return the value — proving cache is used.
        let second = service.retrieve(for: .openAI)
        #expect(second == "key-openai")
    }

    // MARK: - 1.2 Cache miss on first retrieve populates cache

    @Test("Cache miss: first retrieve reads Keychain and populates cache")
    func cacheMissPopulatesCache() {
        let service = KeychainService()
        // Write directly to Keychain, bypassing the service (and cache).
        KeychainService.writeToKeychainOnly("direct-key", for: .deepL)

        let value = service.retrieve(for: .deepL)
        #expect(value == "direct-key")

        // Now evict Keychain entry; cache should still serve the value.
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
        let service = KeychainService()
        service.store("first", for: .openAI)
        #expect(service.retrieve(for: .openAI) == "first")

        service.store("second", for: .openAI)
        #expect(service.retrieve(for: .openAI) == "second")
    }

    // MARK: - 1.5 Retrieve after delete returns nil

    @Test("Retrieve after delete returns nil")
    func retrieveAfterDeleteReturnsNil() {
        let service = KeychainService()
        service.store("to-delete", for: .deepL)
        #expect(service.retrieve(for: .deepL) == "to-delete")

        service.delete(for: .deepL)
        #expect(service.retrieve(for: .deepL) == nil)
    }
}
