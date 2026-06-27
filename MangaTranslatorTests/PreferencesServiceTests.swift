import Testing
import Combine
import Foundation
@testable import MangaTranslator

enum CopilotPreferenceNormalizationCase: CaseIterable, Sendable {
    case autoOnlyUnavailable
    case selectableValid
    case selectableAbsent
    case failedPreserves
    case noCompatiblePreserves
}

@Suite("PreferencesService", .serialized)
struct PreferencesServiceTests {

    private let suiteName = "PreferencesServiceTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
    }

    @Test("Fresh preferences default the Copilot model to Auto")
    func freshPreferencesDefaultCopilotModelToAuto() {
        let preferences = PreferencesService(defaults: defaults)

        #expect(preferences.copilotModel == "auto")
    }

    @Test(
        "Copilot model normalization follows successful catalog capability",
        arguments: CopilotPreferenceNormalizationCase.allCases
    )
    func copilotModelNormalizationFollowsCatalogCapability(
        _ testCase: CopilotPreferenceNormalizationCase
    ) {
        let concrete = CopilotModel(
            id: "concrete",
            name: "Concrete",
            category: nil,
            pickerEnabled: true,
            supportedEndpoints: ["/chat/completions"]
        )
        let state: CopilotModelLoadState
        let stored: String
        let expected: String

        switch testCase {
        case .autoOnlyUnavailable:
            (state, stored, expected) = (.autoOnly, "unavailable", "auto")
        case .selectableValid:
            (state, stored, expected) = (.selectable([.auto, concrete]), "concrete", "concrete")
        case .selectableAbsent:
            (state, stored, expected) = (.selectable([.auto, concrete]), "absent", "auto")
        case .failedPreserves:
            (state, stored, expected) = (.failed("Couldn’t load Copilot models."), "saved", "saved")
        case .noCompatiblePreserves:
            (state, stored, expected) = (.noCompatibleModels, "saved", "saved")
        }

        #expect(state.normalizedCopilotModel(stored) == expected)
    }

    // MARK: - Two independent instances do NOT share state

    @Test("Two independent PreferencesService instances do not share in-memory state")
    func independentInstancesDoNotShareState() {
        let defaultsA = UserDefaults(suiteName: "\(suiteName).a")!
        defaultsA.removePersistentDomain(forName: "\(suiteName).a")
        let defaultsB = UserDefaults(suiteName: "\(suiteName).b")!
        defaultsB.removePersistentDomain(forName: "\(suiteName).b")

        let a = PreferencesService(defaults: defaultsA)
        let b = PreferencesService(defaults: defaultsB)

        a.targetLanguage = .en

        #expect(a.targetLanguage == .en)
        #expect(b.targetLanguage == .zhHant,
                "Separate instances backed by different defaults must not share state")
    }

    // MARK: - ViewModel forwards objectWillChange from nested PreferencesService

    @Test("TranslationViewModel.objectWillChange fires when a preference changes")
    @MainActor
    func viewModelForwardsNestedObjectWillChange() {
        let preferences = PreferencesService(defaults: defaults)
        let viewModel = TranslationViewModel(preferences: preferences)

        var didFire = false
        let cancellable = viewModel.objectWillChange.sink { didFire = true }

        preferences.targetLanguage = .en

        #expect(didFire, "viewModel.objectWillChange must forward changes from preferences so SwiftUI re-renders the toolbar")
        _ = cancellable
    }

    // MARK: - Shared instance is reflected in TranslationViewModel

    @Test("TranslationViewModel reflects changes made to the shared PreferencesService")
    @MainActor
    func sharedInstanceReflectedInViewModel() {
        let preferences = PreferencesService(defaults: defaults)
        let viewModel = TranslationViewModel(preferences: preferences)

        preferences.targetLanguage = .en

        #expect(viewModel.preferences.targetLanguage == .en)
    }

    @Test("PreferencesService persists values into its injected UserDefaults store")
    func preferencesPersistIntoInjectedDefaults() {
        let preferences = PreferencesService(defaults: defaults)

        preferences.openAIBaseURL = "https://example.invalid/v1"
        preferences.translationEngine = .google

        let reloaded = PreferencesService(defaults: defaults)
        #expect(reloaded.openAIBaseURL == "https://example.invalid/v1")
        #expect(reloaded.translationEngine == .google)
    }

    @Test("Persisted zh-Hant source language is migrated to ja on init")
    func persistedInvalidSourceLanguageMigratedToJa() {
        let migrationSuiteName = "\(suiteName).migration"
        let migrationDefaults = UserDefaults(suiteName: migrationSuiteName)!
        migrationDefaults.removePersistentDomain(forName: migrationSuiteName)
        migrationDefaults.set("zh-Hant", forKey: "sourceLanguage")

        let preferences = PreferencesService(defaults: migrationDefaults)

        #expect(preferences.sourceLanguage == .ja,
                "A persisted 'zh-Hant' sourceLanguage must be reset to .ja because it is not a valid source language")
    }

    @Test("Invalid Base URL is not written to UserDefaults")
    func invalidBaseURLNotPersistedToDefaults() {
        let preferences = PreferencesService(defaults: defaults)
        let validURL = preferences.openAIBaseURL

        preferences.openAIBaseURL = "http://evil.example.com/steal?key=1"

        let reloaded = PreferencesService(defaults: defaults)
        #expect(reloaded.openAIBaseURL == validURL,
                "UserDefaults must not be updated when the base URL is invalid")
    }

    @Test("Base URL with query string is not written to UserDefaults")
    func queryStringBaseURLNotPersistedToDefaults() {
        let preferences = PreferencesService(defaults: defaults)
        preferences.openAIBaseURL = "https://api.openai.com/v1"

        preferences.openAIBaseURL = "https://api.openai.com/v1?leak=key"

        let reloaded = PreferencesService(defaults: defaults)
        #expect(reloaded.openAIBaseURL == "https://api.openai.com/v1",
                "UserDefaults must retain last valid URL when a URL with a query string is set")
    }

    // MARK: - activeTabIdentifier is not persisted

    @Test("activeTabIdentifier defaults to 'apiKeys' on fresh init")
    func activeTabIdentifierDefaultsToApiKeys() {
        let preferences = PreferencesService(defaults: defaults)
        #expect(preferences.activeTabIdentifier == "apiKeys")
    }

    @Test("activeTabIdentifier mutation is not written to UserDefaults")
    func activeTabIdentifierNotWrittenToUserDefaults() {
        let preferences = PreferencesService(defaults: defaults)
        preferences.activeTabIdentifier = "glossary"

        // A fresh instance from the same defaults must still read the default value,
        // proving that the mutation was never persisted.
        let reloaded = PreferencesService(defaults: defaults)
        #expect(reloaded.activeTabIdentifier == "apiKeys",
                "activeTabIdentifier must not be persisted; reloaded instance must start at 'apiKeys'")
    }

    @Test("activeTabIdentifier is not present in UserDefaults after mutation")
    func activeTabIdentifierAbsentFromUserDefaultsAfterMutation() {
        let suiteName2 = "\(suiteName).tabKey"
        let defaults2 = UserDefaults(suiteName: suiteName2)!
        defaults2.removePersistentDomain(forName: suiteName2)

        let preferences = PreferencesService(defaults: defaults2)
        preferences.activeTabIdentifier = "debug"

        #expect(defaults2.object(forKey: "activeTabIdentifier") == nil,
                "UserDefaults must contain no 'activeTabIdentifier' key at all")
    }
}
