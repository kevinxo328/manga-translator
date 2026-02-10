import Foundation
import Security

struct KeychainService {
    private let serviceName = "com.chunweiliu.MangaTranslator"

    func store(_ apiKey: String, for engine: TranslationEngine) {
        let account = engine.rawValue
        delete(for: engine)

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

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(for engine: TranslationEngine) {
        let account = engine.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    func hasKey(for engine: TranslationEngine) -> Bool {
        retrieve(for: engine) != nil
    }
}
