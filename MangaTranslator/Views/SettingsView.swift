import SwiftUI

struct SettingsView: View {
    @StateObject private var preferences = PreferencesService()
    private let keychainService = KeychainService()

    @State private var deepLKey = ""
    @State private var googleKey = ""
    @State private var openAIKey = ""
    @State private var claudeKey = ""

    var body: some View {
        TabView {
            apiKeysTab
                .tabItem { Label("API Keys", systemImage: "key") }

            preferencesTab
                .tabItem { Label("Preferences", systemImage: "gearshape") }
        }
        .frame(width: 450, height: 350)
        .onAppear { loadKeys() }
    }

    private var apiKeysTab: some View {
        Form {
            Section("DeepL") {
                SecureField("API Key", text: $deepLKey)
                    .onChange(of: deepLKey) { newValue in
                        saveKey(newValue, for: .deepL)
                    }
            }
            Section("Google Translate") {
                SecureField("API Key", text: $googleKey)
                    .onChange(of: googleKey) { newValue in
                        saveKey(newValue, for: .google)
                    }
            }
            Section("OpenAI") {
                SecureField("API Key", text: $openAIKey)
                    .onChange(of: openAIKey) { newValue in
                        saveKey(newValue, for: .openAI)
                    }
            }
            Section("Anthropic (Claude)") {
                SecureField("API Key", text: $claudeKey)
                    .onChange(of: claudeKey) { newValue in
                        saveKey(newValue, for: .claude)
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var preferencesTab: some View {
        Form {
            Picker("Source Language", selection: $preferences.sourceLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            Picker("Target Language", selection: $preferences.targetLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            Picker("Translation Engine", selection: $preferences.translationEngine) {
                ForEach(TranslationEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func loadKeys() {
        deepLKey = keychainService.retrieve(for: .deepL) ?? ""
        googleKey = keychainService.retrieve(for: .google) ?? ""
        openAIKey = keychainService.retrieve(for: .openAI) ?? ""
        claudeKey = keychainService.retrieve(for: .claude) ?? ""
    }

    private func saveKey(_ key: String, for engine: TranslationEngine) {
        if key.isEmpty {
            keychainService.delete(for: engine)
        } else {
            keychainService.store(key, for: engine)
        }
    }
}
