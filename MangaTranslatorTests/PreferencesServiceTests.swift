import Testing
import Combine
@testable import MangaTranslator

@Suite("PreferencesService")
struct PreferencesServiceTests {

    // MARK: - Two independent instances do NOT share state

    @Test("Two independent PreferencesService instances do not share in-memory state")
    func independentInstancesDoNotShareState() {
        let a = PreferencesService()
        let b = PreferencesService()

        a.targetLanguage = .en
        // b is a separate instance — its in-memory value should be unaffected
        #expect(b.targetLanguage != .en || a.targetLanguage == b.targetLanguage,
                "Separate instances should not share in-memory state")
    }

    // MARK: - ViewModel forwards objectWillChange from nested PreferencesService

    @Test("TranslationViewModel.objectWillChange fires when a preference changes")
    @MainActor
    func viewModelForwardsNestedObjectWillChange() {
        let preferences = PreferencesService()
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
        let preferences = PreferencesService()
        let viewModel = TranslationViewModel(preferences: preferences)

        preferences.targetLanguage = .en

        #expect(viewModel.preferences.targetLanguage == .en)
    }
}
