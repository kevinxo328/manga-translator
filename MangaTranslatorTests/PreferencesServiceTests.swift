import Testing
import Combine
import Foundation
@testable import MangaTranslator

@Suite("PreferencesService", .serialized)
struct PreferencesServiceTests {

    private let suiteName = "PreferencesServiceTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
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
}
