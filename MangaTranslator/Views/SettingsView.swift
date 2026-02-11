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
    
    @State private var selectedOpenAIModel: String = ""
    @State private var selectedClaudeModel: String = ""
    @State private var customOpenAIModel: String = ""
    @State private var customClaudeModel: String = ""

    var body: some View {
        TabView {
            apiKeysTab
                .tabItem { Label("API Keys", systemImage: "key") }

            preferencesTab
                .tabItem { Label("Preferences", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
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
                
                Picker("Model", selection: $selectedOpenAIModel) {
                    ForEach(TranslationEngine.openAIModels) { model in
                        Text(model.displayName).tag(model.apiIdentifier)
                    }
                    Text("Custom...").tag("custom")
                }
                .onChange(of: selectedOpenAIModel) { newValue in
                    if newValue != "custom" {
                        preferences.openAIModel = newValue
                    } else {
                        preferences.openAIModel = customOpenAIModel
                    }
                }
                
                if selectedOpenAIModel == "custom" {
                    TextField("Model ID", text: $customOpenAIModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customOpenAIModel) { newValue in
                            preferences.openAIModel = newValue
                        }
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
                
                Picker("Model", selection: $selectedClaudeModel) {
                    ForEach(TranslationEngine.claudeModels) { model in
                        Text(model.displayName).tag(model.apiIdentifier)
                    }
                    Text("Custom...").tag("custom")
                }
                .onChange(of: selectedClaudeModel) { newValue in
                    if newValue != "custom" {
                        preferences.claudeModel = newValue
                    } else {
                        preferences.claudeModel = customClaudeModel
                    }
                }
                
                if selectedClaudeModel == "custom" {
                    TextField("Model ID", text: $customClaudeModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customClaudeModel) { newValue in
                            preferences.claudeModel = newValue
                        }
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

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("MangaTranslator")
                .font(.title.bold())

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .foregroundStyle(.secondary)

            Text("© 2026 Chun-Wei Liu. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Link(destination: URL(string: "mailto:kevinxo328@gmail.com")!) {
                    Label("kevinxo328@gmail.com", systemImage: "envelope")
                }
                Link(destination: URL(string: "https://github.com/kevinxo328")!) {
                    Label("GitHub", systemImage: "link")
                }
            }
            .font(.callout)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadKeys() {
        deepLKey = keychainService.retrieve(for: .deepL) ?? ""
        googleKey = keychainService.retrieve(for: .google) ?? ""
        openAIKey = keychainService.retrieve(for: .openAI) ?? ""
        claudeKey = keychainService.retrieve(for: .claude) ?? ""
        
        // Initialize model selection states
        if let _ = TranslationEngine.openAIModels.first(where: { $0.apiIdentifier == preferences.openAIModel }) {
            selectedOpenAIModel = preferences.openAIModel
        } else {
            selectedOpenAIModel = "custom"
            customOpenAIModel = preferences.openAIModel
        }
        
        if let _ = TranslationEngine.claudeModels.first(where: { $0.apiIdentifier == preferences.claudeModel }) {
            selectedClaudeModel = preferences.claudeModel
        } else {
            selectedClaudeModel = "custom"
            customClaudeModel = preferences.claudeModel
        }
    }

    private func saveKey(_ key: String, for engine: TranslationEngine) {
        if key.isEmpty {
            keychainService.delete(for: engine)
        } else {
            keychainService.store(key, for: engine)
        }
    }
}
