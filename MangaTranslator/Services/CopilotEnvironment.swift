import Foundation
import Security

enum CopilotAvailability: Equatable {
    case available(token: String)
    case notInstalled
    case notLoggedIn
}

struct CopilotEnvironment {

    // MARK: - Availability

    static func check() -> CopilotAvailability {
        guard binaryPath(searchingIn: defaultSearchPaths) != nil else {
            return .notInstalled
        }
        guard let token = readKeychainToken() else {
            return .notLoggedIn
        }
        return .available(token: token)
    }

    // MARK: - Model fetching

    static func fetchModels(token: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://api.individual.githubcopilot.com/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("copilot-developer-cli", forHTTPHeaderField: "Copilot-Integration-Id")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return filterChatModels(decoded.data.map(\.id))
    }

    // MARK: - Internal (internal for testing)

    static func filterChatModels(_ ids: [String]) -> [String] {
        ids.filter { !$0.hasPrefix("text-embedding") }.sorted()
    }

    static func binaryPath(searchingIn paths: [String]) -> String? {
        paths.first { path in
            FileManager.default.fileExists(atPath: "\(path)/copilot")
        }
    }

    // MARK: - Private

    private static var defaultSearchPaths: [String] {
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .components(separatedBy: ":")
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/sbin"]
        for path in extraPaths where !paths.contains(path) {
            paths.append(path)
        }
        return paths
    }

    private static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "copilot-cli",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }
}

extension CopilotAvailability {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}
