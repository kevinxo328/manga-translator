import SwiftUI

struct SettingsView: View {
    @StateObject private var preferences = PreferencesService()
    private let keychainService = KeychainService()
    var onClearCache: (() -> Void)?

    @State private var deepLKey = ""
    @State private var googleKey = ""
    @State private var openAIKey = ""
    @State private var claudeKey = ""
    @State private var showClearCacheAlert = false

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
            Section {
                SecureField("API Key", text: $deepLKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: deepLKey) { newValue in
                        saveKey(newValue, for: .deepL)
                    }
            } header: {
                Label("DeepL", systemImage: "globe.europe.africa")
            } footer: {
                Text("Required for DeepL translation.")
            }

            Section {
                SecureField("API Key", text: $googleKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: googleKey) { newValue in
                        saveKey(newValue, for: .google)
                    }
            } header: {
                Label("Google Translate", systemImage: "g.circle")
            }

            Section {
                SecureField("API Key", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: openAIKey) { newValue in
                        saveKey(newValue, for: .openAI)
                    }
            } header: {
                Label("OpenAI", systemImage: "brain")
            }

            Section {
                SecureField("API Key", text: $claudeKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: claudeKey) { newValue in
                        saveKey(newValue, for: .claude)
                    }
            } header: {
                Label("Anthropic (Claude)", systemImage: "sparkles")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var preferencesTab: some View {
        Form {
            Section {
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
            } header: {
                Label("Translation Defaults", systemImage: "gear")
            }

            if onClearCache != nil {
                Section {
                    Button(role: .destructive) {
                        showClearCacheAlert = true
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                } header: {
                    Label("Cache", systemImage: "internaldrive")
                } footer: {
                    Text("Removes all cached translations. Pages will be re-translated on next run.")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Clear Cache", isPresented: $showClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                onClearCache?()
            }
        } message: {
            Text("This will delete all cached translation results. This action cannot be undone.")
        }
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
