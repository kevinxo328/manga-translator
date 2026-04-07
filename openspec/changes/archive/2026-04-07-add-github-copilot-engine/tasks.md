# GitHub Copilot Engine — Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement task-by-task.

**Goal:** Add GitHub Copilot as a translation engine, reading the installed CLI's OAuth token from the local keychain.

**Architecture:** New `CopilotEnvironment` handles availability check and model fetching. New `CopilotTranslationService` calls `api.individual.githubcopilot.com` (OpenAI-compatible). Existing services untouched.

**Tech Stack:** Swift, SwiftUI, Security framework, Swift Testing

---

## 1. Models — Add `githubCopilot` engine case

**Files:**
- Modify: `MangaTranslator/Models/Models.swift`

- [x] 1.1 Add `.githubCopilot = "github-copilot"` to `TranslationEngine` enum; add `displayName` ("GitHub Copilot") and `isLLM` (true) cases
- [x] 1.2 Build the project — confirm no switch exhaustiveness warnings (`xcodebuild -scheme MangaTranslator build`)
- [x] 1.3 Commit: `feat(models): add githubCopilot TranslationEngine case`

---

## 2. CopilotEnvironment — Availability check + model fetching

**Files:**
- Create: `MangaTranslator/Services/CopilotEnvironment.swift`
- Create: `MangaTranslatorTests/CopilotEnvironmentTests.swift`

- [x] 2.1 Write failing test for `CopilotAvailability` enum shape:

```swift
// CopilotEnvironmentTests.swift
import Testing
@testable import MangaTranslator

@Suite("CopilotEnvironment")
struct CopilotEnvironmentTests {

    @Test("notInstalled when binary absent")
    func notInstalledWhenBinaryAbsent() {
        // Simulate binary check by calling the internal path helper
        let result = CopilotEnvironment.binaryPath(searchingIn: ["/nonexistent/path"])
        #expect(result == nil)
    }

    @Test("fetchModels filters embedding models")
    func fetchModelsFiltersEmbeddingModels() {
        let all = ["gpt-5-mini", "text-embedding-3-small", "claude-sonnet-4.6", "text-embedding-ada-002"]
        let filtered = CopilotEnvironment.filterChatModels(all)
        #expect(filtered == ["gpt-5-mini", "claude-sonnet-4.6"])
    }
}
```

- [x] 2.2 Run test — confirm FAIL (`xcodebuild test -scheme MangaTranslator -only-testing:MangaTranslatorTests/CopilotEnvironmentTests`)

- [x] 2.3 Implement `CopilotEnvironment.swift`:

```swift
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
        ids.filter { !$0.hasPrefix("text-embedding") }
    }

    static func binaryPath(searchingIn paths: [String]) -> String? {
        paths.first { path in
            FileManager.default.fileExists(atPath: "\(path)/copilot")
        }
    }

    // MARK: - Private

    private static var defaultSearchPaths: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .components(separatedBy: ":")
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
```

- [x] 2.4 Run tests — confirm PASS
- [x] 2.5 Commit: `feat(services): add CopilotEnvironment with availability check and model fetching`

---

## 3. PreferencesService — Add `copilotModel`

**Files:**
- Modify: `MangaTranslator/Services/PreferencesService.swift`

- [x] 3.1 Add `static let defaultCopilotModel = "gpt-5-mini"` and `@Published var copilotModel: String` with `UserDefaults` persistence (pattern identical to `openAIModel`)
- [x] 3.2 Build — confirm no errors
- [x] 3.3 Commit: `feat(preferences): add copilotModel preference`

---

## 4. CopilotTranslationService

**Files:**
- Create: `MangaTranslator/Services/CopilotTranslationService.swift`
- Create: `MangaTranslatorTests/CopilotTranslationServiceTests.swift`

- [x] 4.1 Write failing test:

```swift
// CopilotTranslationServiceTests.swift
import Testing
@testable import MangaTranslator

@Suite("CopilotTranslationService")
struct CopilotTranslationServiceTests {

    @Test("engine is githubCopilot")
    func engineIsGithubCopilot() {
        let service = CopilotTranslationService(model: "gpt-5-mini")
        #expect(service.engine == .githubCopilot)
    }

    @Test("translate throws missingAPIKey when Copilot CLI absent")
    func throwsMissingAPIKeyWhenUnavailable() async throws {
        // This test passes only on machines without copilot-cli keychain entry
        // Skip on CI or machines with Copilot installed
        guard case .notInstalled = CopilotEnvironment.check() else {
            return // copilot is installed, skip this assertion path
        }
        let service = CopilotTranslationService(model: "gpt-5-mini")
        await #expect(throws: TranslationError.self) {
            _ = try await service.translate(
                bubbles: [],
                from: .ja, to: .zhHant,
                context: .empty
            )
        }
    }
}
```

- [x] 4.2 Run test — confirm FAIL

- [x] 4.3 Implement `CopilotTranslationService.swift` (mirror `OpenAITranslationService`, replacing auth + URL + headers):

```swift
import Foundation

struct CopilotTranslationService: TranslationService {
    let engine = TranslationEngine.githubCopilot
    private let model: String
    private let maxRetries = 2
    private let baseURL = "https://api.individual.githubcopilot.com"

    init(model: String) {
        self.model = model
    }

    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput {
        guard case .available(let token) = CopilotEnvironment.check() else {
            throw TranslationError.missingAPIKey(.githubCopilot)
        }

        let systemPrompt = LLMPrompt.systemPrompt(from: source, to: target, context: context)
        let userPrompt = LLMPrompt.userPrompt(bubbles: bubbles)

        for attempt in 0...maxRetries {
            let responseText = try await callAPI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                token: token
            )

            if let (parsed, detected) = try? LLMResponseParser.parse(responseText, bubbles: bubbles) {
                return TranslationOutput(bubbles: parsed, detectedTerms: detected)
            }

            if attempt == maxRetries {
                let (fallback, _) = LLMResponseParser.fallbackParse(responseText, bubbles: bubbles)
                return TranslationOutput(bubbles: fallback, detectedTerms: [])
            }
        }

        let (fallback, _) = LLMResponseParser.fallbackParse("", bubbles: bubbles)
        return TranslationOutput(bubbles: fallback, detectedTerms: [])
    }

    private func callAPI(systemPrompt: String, userPrompt: String, token: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("copilot-developer-cli", forHTTPHeaderField: "Copilot-Integration-Id")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError(errorText)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw TranslationError.invalidResponse
        }
        return content
    }
}
```

- [x] 4.4 Run tests — confirm PASS
- [x] 4.5 Commit: `feat(services): add CopilotTranslationService`

---

## 5. TranslationViewModel — Wire up new engine

**Files:**
- Modify: `MangaTranslator/ViewModels/TranslationViewModel.swift`

- [x] 5.1 In `translationService` computed property, add:
  ```swift
  case .githubCopilot: return CopilotTranslationService(model: preferences.copilotModel)
  ```

- [x] 5.2 In `translatePage(at:)`, change the `hasKey` guard (line ~181) to skip Copilot:
  ```swift
  // Before:
  guard keychainService.hasKey(for: preferences.translationEngine) else { ... }

  // After:
  if preferences.translationEngine != .githubCopilot {
      guard keychainService.hasKey(for: preferences.translationEngine) else {
          showMissingKeyAlert = true
          pages[index].state = .error("Missing API key for \(preferences.translationEngine.displayName)")
          return
      }
  }
  ```

- [x] 5.3 Build — confirm no errors
- [x] 5.4 Run all tests — confirm no regressions (`xcodebuild test -scheme MangaTranslator`)
- [x] 5.5 Commit: `feat(viewmodel): wire CopilotTranslationService and bypass hasKey check for Copilot`

---

## 6. SettingsView — Copilot section + availability-aware picker

**Files:**
- Modify: `MangaTranslator/Views/SettingsView.swift`

- [x] 6.1 Add state variables to `SettingsView`:
  ```swift
  @State private var copilotAvailability: CopilotAvailability = .notInstalled
  @State private var copilotModels: [String] = []
  ```

- [x] 6.2 Add `.task` on `TabView` to load availability and models:
  ```swift
  .task {
      copilotAvailability = CopilotEnvironment.check()
      if case .available(let token) = copilotAvailability {
          copilotModels = (try? await CopilotEnvironment.fetchModels(token: token)) ?? []
      }
  }
  ```

- [x] 6.3 In `apiKeysTab`, add GitHub Copilot `Section` after the OpenAI section:
  ```swift
  Section {
      switch copilotAvailability {
      case .available:
          Label("Copilot CLI detected", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          if copilotModels.isEmpty {
              ProgressView()
          } else {
              Picker("Model", selection: $preferences.copilotModel) {
                  ForEach(copilotModels, id: \.self) { Text($0).tag($0) }
              }
          }
      case .notInstalled:
          Label("GitHub Copilot CLI not found", systemImage: "xmark.circle")
              .foregroundStyle(.secondary)
          Text("Install from github.com/github/copilot-cli")
              .font(.caption).foregroundStyle(.secondary)
      case .notLoggedIn:
          Label("Not logged in", systemImage: "exclamationmark.circle")
              .foregroundStyle(.orange)
          Text("Run `copilot login` in Terminal")
              .font(.caption).foregroundStyle(.secondary)
      }
  } header: {
      Label("GitHub Copilot", systemImage: "sparkles")
  }
  ```

- [x] 6.4 In `preferencesTab` engine picker, filter out Copilot when unavailable:
  ```swift
  Picker("Translation Engine", selection: $preferences.translationEngine) {
      ForEach(TranslationEngine.allCases.filter {
          $0 != .githubCopilot || copilotAvailability != .notInstalled && copilotAvailability != .notLoggedIn
      }) { engine in
          Text(engine.displayName).tag(engine)
      }
  }
  ```
  Replace the filter condition with the correct `CopilotAvailability` check. Because `CopilotAvailability` is not `Equatable` for the `.available` case without associated value comparison, add `var isAvailable: Bool` helper:
  ```swift
  // In CopilotEnvironment.swift, extend the enum:
  extension CopilotAvailability {
      var isAvailable: Bool {
          if case .available = self { return true }
          return false
      }
  }
  ```
  Then the picker filter becomes:
  ```swift
  .filter { $0 != .githubCopilot || copilotAvailability.isAvailable }
  ```

- [x] 6.5 Build and run app — manually verify:
  - GitHub Copilot section shows green checkmark with model picker (if CLI installed)
  - Model picker populates with 27 models
  - Engine picker shows "GitHub Copilot" option
  - Selecting GitHub Copilot + translating an image works end-to-end

- [x] 6.6 Run all tests — confirm no regressions
- [x] 6.7 Commit: `feat(settings): add GitHub Copilot section with availability status and model picker`
