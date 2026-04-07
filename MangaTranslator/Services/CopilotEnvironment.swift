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

    static func fetchModels(token: String) async throws -> [CopilotModel] {
        let endpoints = [
            "https://api.individual.githubcopilot.com/models",
            "https://api.githubcopilot.com/models"
        ]
        for endpoint in endpoints {
            if let models = try? await fetchModelsFromEndpoint(token: token, urlString: endpoint),
               !models.isEmpty {
                return models
            }
        }
        return []
    }

    // MARK: - Internal (internal for testing)

    static func fetchModelsFromEndpoint(token: String, urlString: String) async throws -> [CopilotModel] {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[CopilotEnv] raw models response:\n\(raw)")
        }
        return try parseModels(data)
    }

    static func parseModels(_ data: Data) throws -> [CopilotModel] {
        struct APIResponse: Decodable {
            struct Model: Decodable {
                let id: String
                let name: String?
                let modelPickerEnabled: Bool?
                let modelPickerCategory: String?

                enum CodingKeys: String, CodingKey {
                    case id, name
                    case modelPickerEnabled = "model_picker_enabled"
                    case modelPickerCategory = "model_picker_category"
                }
            }
            let data: [Model]
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.data
            .filter { $0.modelPickerEnabled == true }
            .map { model in
                CopilotModel(
                    id: model.id,
                    name: model.name ?? model.id,
                    category: model.modelPickerCategory
                )
            }
            .sorted { $0.name < $1.name }
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
