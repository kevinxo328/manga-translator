import Foundation
import Security

struct KeychainService {
    private let serviceName = "com.chunweiliu.MangaTranslator"

    // In-memory cache shared across all instances within a session.
    // Reduces Keychain access after the initial authorization prompt.
    private static var cache: [String: String] = [:]

    // MARK: - Public API

    func store(_ apiKey: String, for engine: TranslationEngine) {
        // Write to cache first so retrieve() reflects the change immediately.
        Self.cache[engine.rawValue] = apiKey

        let account = engine.rawValue
        delete(keychainOnly: true, account: account)

        guard let data = apiKey.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func retrieve(for engine: TranslationEngine) -> String? {
        let account = engine.rawValue

        // Return cached value if available.
        if let cached = Self.cache[account] {
            return cached
        }

        // Cache miss: read from Keychain and populate cache.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }

        Self.cache[account] = value
        return value
    }

    func delete(for engine: TranslationEngine) {
        Self.cache.removeValue(forKey: engine.rawValue)
        delete(keychainOnly: true, account: engine.rawValue)
    }

    func hasKey(for engine: TranslationEngine) -> Bool {
        retrieve(for: engine) != nil
    }

    // MARK: - Private helpers

    private func delete(keychainOnly: Bool, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Test support

    static func clearCache() {
        cache = [:]
    }

    /// Writes directly to Keychain without touching the in-memory cache.
    /// Used in tests to simulate a cache miss on first retrieve.
    static func writeToKeychainOnly(_ apiKey: String, for engine: TranslationEngine) {
        let serviceName = "com.chunweiliu.MangaTranslator"
        let account = engine.rawValue

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let data = apiKey.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Removes a Keychain entry without touching the in-memory cache.
    /// Used in tests to verify that subsequent retrieve() uses the cache.
    static func evictFromKeychainOnly(for engine: TranslationEngine) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.chunweiliu.MangaTranslator",
            kSecAttrAccount as String: engine.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
