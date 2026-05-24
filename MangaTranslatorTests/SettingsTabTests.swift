import Testing
import Foundation
@testable import MangaTranslator

@Suite("SettingsTab identifier mapping")
struct SettingsTabTests {

    // MARK: - from(identifier:) known values

    @Test("Known identifier 'apiKeys' maps to .apiKeys")
    func apiKeysIdentifierMapsCorrectly() {
        #expect(SettingsTab.from(identifier: "apiKeys") == .apiKeys)
    }

    @Test("Known identifier 'preferences' maps to .preferences")
    func preferencesIdentifierMapsCorrectly() {
        #expect(SettingsTab.from(identifier: "preferences") == .preferences)
    }

    @Test("Known identifier 'debug' maps to .debug")
    func debugIdentifierMapsCorrectly() {
        #expect(SettingsTab.from(identifier: "debug") == .debug)
    }

    @Test("Known identifier 'about' maps to .about")
    func aboutIdentifierMapsCorrectly() {
        #expect(SettingsTab.from(identifier: "about") == .about)
    }

    @Test("Known identifier 'glossary' maps to .glossary")
    func glossaryIdentifierMapsCorrectly() {
        #expect(SettingsTab.from(identifier: "glossary") == .glossary)
    }

    // MARK: - from(identifier:) fallback

    @Test("Unknown identifier falls back to .apiKeys")
    func unknownIdentifierFallsBackToApiKeys() {
        #expect(SettingsTab.from(identifier: "bogus") == .apiKeys)
        #expect(SettingsTab.from(identifier: "") == .apiKeys)
        #expect(SettingsTab.from(identifier: "Glossary") == .apiKeys) // case-sensitive
    }

    // MARK: - round-trip: identifier → tab → identifier

    @Test("Tab identifier round-trips through from(identifier:)")
    func tabIdentifierRoundTrips() {
        for tab in SettingsTab.allCases {
            #expect(SettingsTab.from(identifier: tab.identifier) == tab,
                    "Tab '\(tab.identifier)' must round-trip through from(identifier:)")
        }
    }

    // MARK: - deep-link: PreferencesService drives Glossary tab selection

    @Test("Setting activeTabIdentifier to 'glossary' resolves to .glossary tab")
    func deepLinkToGlossaryTab() {
        let defaults = UserDefaults(suiteName: "SettingsTabTests.\(UUID().uuidString)")!
        let preferences = PreferencesService(defaults: defaults)

        preferences.activeTabIdentifier = "glossary"

        #expect(SettingsTab.from(identifier: preferences.activeTabIdentifier) == .glossary,
                "Manage Glossaries... deep-link must select the Glossary tab")
    }

    @Test("Unknown activeTabIdentifier resolves to .apiKeys tab")
    func deepLinkWithUnknownIdentifierFallsBack() {
        let defaults = UserDefaults(suiteName: "SettingsTabTests.\(UUID().uuidString)")!
        let preferences = PreferencesService(defaults: defaults)

        preferences.activeTabIdentifier = "invalid"

        #expect(SettingsTab.from(identifier: preferences.activeTabIdentifier) == .apiKeys,
                "Unknown identifier must display API Keys tab as fallback")
    }

    // MARK: - normalizeIdentifier

    @Test("normalizeIdentifier writes 'apiKeys' back when identifier is unknown")
    func normalizationWritesBackApiKeys() {
        let defaults = UserDefaults(suiteName: "SettingsTabTests.\(UUID().uuidString)")!
        let preferences = PreferencesService(defaults: defaults)

        preferences.activeTabIdentifier = "invalid"
        SettingsTab.normalizeIdentifier(in: preferences)

        #expect(preferences.activeTabIdentifier == "apiKeys",
                "normalizeIdentifier must write 'apiKeys' back when identifier is unknown")
    }

    @Test("normalizeIdentifier is a no-op for valid identifiers")
    func normalizationIsNoOpForValidIdentifiers() {
        let defaults = UserDefaults(suiteName: "SettingsTabTests.\(UUID().uuidString)")!
        let preferences = PreferencesService(defaults: defaults)

        preferences.activeTabIdentifier = "glossary"
        SettingsTab.normalizeIdentifier(in: preferences)

        #expect(preferences.activeTabIdentifier == "glossary",
                "normalizeIdentifier must not change a valid identifier")
    }
}
