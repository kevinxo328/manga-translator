import Foundation
import Security
import CryptoKit

actor CopilotModelCatalogStore {
    static let shared = CopilotModelCatalogStore()

    private struct Key: Hashable {
        let host: URL
        let accountDigest: String
    }

    private struct Entry {
        let models: [CopilotModel]
        let fetchedAt: Date
    }

    private let now: @Sendable () -> Date
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<[CopilotModel], Error>] = [:]
    private var accountDigestByHost: [URL: String] = [:]

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func models(
        host: URL,
        token: String,
        fetch: @escaping @Sendable () async throws -> [CopilotModel]
    ) async throws -> [CopilotModel] {
        let accountDigest = Self.digest(token)
        let key = Key(host: host, accountDigest: accountDigest)
        let currentTime = now()
        entries = entries.filter { currentTime.timeIntervalSince($0.value.fetchedAt) < 300 }

        if let existingDigest = accountDigestByHost[host], existingDigest != accountDigest {
            entries = entries.filter { $0.key.host != host }
            let supersededKeys = inFlight.keys.filter { $0.host == host }
            for supersededKey in supersededKeys {
                inFlight[supersededKey]?.cancel()
                inFlight[supersededKey] = nil
            }
        }
        accountDigestByHost[host] = accountDigest

        if let entry = entries[key], currentTime.timeIntervalSince(entry.fetchedAt) < 300 {
            return entry.models
        }
        entries[key] = nil

        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await fetch() }
        inFlight[key] = task
        do {
            let models = try await task.value
            inFlight[key] = nil
            if accountDigestByHost[host] == accountDigest {
                entries[key] = Entry(models: models, fetchedAt: now())
            }
            return models
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func invalidate(host: URL, token: String) {
        let key = Key(host: host, accountDigest: Self.digest(token))
        entries[key] = nil
        inFlight[key]?.cancel()
        inFlight[key] = nil
    }

    private static func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum CopilotAvailability: Equatable {
    case available(token: String)
    case notInstalled
    case notLoggedIn
}

struct CopilotEnvironment {
    static let copilotAPIVersion = "2026-07-01"
    static let copilotIntegrationID = "copilot-developer-cli"
    static let individualHost = URL(string: "https://api.individual.githubcopilot.com")!
    static let businessHost = URL(string: "https://api.githubcopilot.com")!
    static let catalogHosts = [individualHost, businessHost]

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

    static func fetchModels(token: String, session: URLSession = .shared) async throws -> CopilotModelCatalogResult {
        let hosts = catalogHosts
        var lastError: Error = TranslationError.invalidResponse
        for host in hosts {
            let endpoint = host.appending(path: "models").absoluteString
            do {
                let models = try await fetchModelsFromEndpoint(
                    token: token,
                    urlString: endpoint,
                    session: session
                )
                if !models.isEmpty {
                    return CopilotModelCatalogResult(host: host, catalog: CopilotModelCatalog(models: models))
                }
                lastError = TranslationError.invalidResponse
            } catch let error as CancellationError {
                throw error
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch TranslationError.apiError(let error)
                where (400..<500).contains(error.statusCode) && error.statusCode != 404 {
                throw TranslationError.apiError(error)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    static func selectCatalog(
        token: String,
        purpose: CopilotCatalogPurpose,
        session: URLSession = .shared,
        store: CopilotModelCatalogStore = .shared
    ) async throws -> CopilotModelCatalogResult {
        let hosts = catalogHosts
        var lastSuccessfulResult: CopilotModelCatalogResult?
        var retainedAutoOnlyResult: CopilotModelCatalogResult?
        var lastError: Error = TranslationError.invalidResponse

        for host in hosts {
            try Task.checkCancellation()
            do {
                let models = try await store.models(host: host, token: token) {
                    try await fetchModelsFromEndpoint(
                        token: token,
                        urlString: host.appending(path: "models").absoluteString,
                        session: session
                    )
                }
                guard !models.isEmpty else {
                    lastError = TranslationError.invalidResponse
                    continue
                }

                let result = CopilotModelCatalogResult(
                    host: host,
                    catalog: CopilotModelCatalog(models: models)
                )
                lastSuccessfulResult = result

                switch purpose {
                case .auto:
                    if !result.catalog.autoHintModelIDs.isEmpty { return result }
                case .explicit(let modelID):
                    if result.catalog.selectableModels.contains(where: { $0.id == modelID }) {
                        return result
                    }
                case .settings:
                    if !result.catalog.selectableModels.isEmpty { return result }
                    if !result.catalog.autoHintModelIDs.isEmpty && retainedAutoOnlyResult == nil {
                        retainedAutoOnlyResult = result
                    }
                }
            } catch let error as CancellationError {
                throw error
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch TranslationError.apiError(let error)
                where (400..<500).contains(error.statusCode) && error.statusCode != 404 {
                throw TranslationError.apiError(error)
            } catch {
                lastError = error
                if purpose == .settings, let retainedAutoOnlyResult {
                    return retainedAutoOnlyResult
                }
            }
        }

        switch purpose {
        case .auto:
            if lastSuccessfulResult != nil { throw CopilotCatalogSelectionError.noCompatibleModels }
        case .explicit(let modelID):
            if lastSuccessfulResult != nil { throw CopilotCatalogSelectionError.modelUnavailable(modelID) }
        case .settings:
            if let retainedAutoOnlyResult { return retainedAutoOnlyResult }
            if let lastSuccessfulResult { return lastSuccessfulResult }
        }
        throw lastError
    }

    // MARK: - Internal (internal for testing)

    static func fetchModelsFromEndpoint(token: String, urlString: String, session: URLSession = .shared) async throws -> [CopilotModel] {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(copilotIntegrationID, forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue(copilotAPIVersion, forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard httpResponse.statusCode == 200 else {
            let sanitized = APIErrorSanitizer.sanitize(
                provider: .copilot,
                providerDisplayName: TranslationEngine.githubCopilot.displayName,
                statusCode: httpResponse.statusCode,
                responseData: data
            )
            throw TranslationError.apiError(sanitized)
        }
        return try parseModels(data)
    }

    static func parseModels(_ data: Data) throws -> [CopilotModel] {
        struct APIResponse: Decodable {
            struct Model: Decodable {
                struct Capabilities: Decodable {
                    let type: String?
                }

                let id: String
                let name: String?
                let modelPickerEnabled: Bool?
                let modelPickerCategory: String?
                let supportedEndpoints: Set<String>?
                let capabilities: Capabilities?

                enum CodingKeys: String, CodingKey {
                    case id, name
                    case modelPickerEnabled = "model_picker_enabled"
                    case modelPickerCategory = "model_picker_category"
                    case supportedEndpoints = "supported_endpoints"
                    case capabilities
                }
            }
            let data: [Model]
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.data
            .filter { !$0.id.hasPrefix("text-embedding") }
            .map { model in
                CopilotModel(
                    id: model.id,
                    name: model.name ?? model.id,
                    category: model.modelPickerCategory,
                    pickerEnabled: model.modelPickerEnabled,
                    supportedEndpoints: model.supportedEndpoints ?? [],
                    capabilityType: model.capabilities?.type
                )
            }
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

    func allowsEngineSelection(modelState: CopilotModelLoadState) -> Bool {
        guard isAvailable else { return false }
        return modelState != .noCompatibleModels
    }

}
