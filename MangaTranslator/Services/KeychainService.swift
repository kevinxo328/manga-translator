import Foundation
import Security

struct KeychainService {
    private static let serviceName = "com.chunweiliu.MangaTranslator"

    // In-memory cache shared across all instances within a session.
    // Reduces Keychain access after the initial authorization prompt.
    private static var cache: [String: String] = [:]
    private static let cacheLock = NSLock()

    // Injectable for testing; nil means use the real Security API.
    var secItemAdd: ((CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus)? = nil
    var secItemUpdate: ((CFDictionary, CFDictionary) -> OSStatus)? = nil
    var secItemDelete: ((CFDictionary) -> OSStatus)? = nil
    var secItemCopyMatching: ((CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus)? = nil

    // MARK: - Public API

    func store(_ apiKey: String, for engine: TranslationEngine) {
        guard let data = apiKey.data(using: .utf8) else { return }
        let account = engine.rawValue

        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: account
        ]
        let updateFn = secItemUpdate ?? Security.SecItemUpdate
        let updateStatus = updateFn(searchQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecSuccess {
            Self.setCachedValue(apiKey, for: account)
            return
        }

        guard updateStatus == errSecItemNotFound else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let addFn = secItemAdd ?? Security.SecItemAdd
        if addFn(addQuery as CFDictionary, nil) == errSecSuccess {
            Self.setCachedValue(apiKey, for: account)
        }
    }

    func retrieve(for engine: TranslationEngine) -> String? {
        let account = engine.rawValue

        if let cached = Self.cachedValue(for: account) {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let copyFn = secItemCopyMatching ?? Security.SecItemCopyMatching
        let status = copyFn(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }

        Self.setCachedValue(value, for: account)
        return value
    }

    func delete(for engine: TranslationEngine) {
        let account = engine.rawValue
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: account
        ]
        let deleteFn = secItemDelete ?? Security.SecItemDelete
        let status = deleteFn(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            Self.removeCachedValue(for: account)
        }
    }

    func hasKey(for engine: TranslationEngine) -> Bool {
        retrieve(for: engine) != nil
    }

    // MARK: - Test support

    static func clearCache() {
        clearCachedValues()
    }

    private static func cachedValue(for account: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[account]
    }

    private static func setCachedValue(_ value: String, for account: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[account] = value
    }

    private static func removeCachedValue(for account: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeValue(forKey: account)
    }

    private static func clearCachedValues() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache = [:]
    }

    /// Writes directly to Keychain without touching the in-memory cache.
    /// Used in tests to simulate a cache miss on first retrieve.
    static func writeToKeychainOnly(_ apiKey: String, for engine: TranslationEngine) {
        let account = engine.rawValue

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let data = apiKey.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
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
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: engine.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Reads directly from Keychain without touching the in-memory cache.
    /// Used in tests to verify Keychain state independently of cache.
    static func readFromKeychainOnly(for engine: TranslationEngine) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: engine.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
