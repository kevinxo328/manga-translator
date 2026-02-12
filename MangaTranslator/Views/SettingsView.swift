import SwiftUI
import Sparkle

struct SettingsView: View {
    @StateObject private var preferences = PreferencesService()
    private let keychainService = KeychainService()
    var onClearCache: (() -> Void)?
    private let updater: SPUUpdater?

    @State private var deepLKey = ""
    @State private var googleKey = ""
    @State private var openAIKey = ""
    @State private var claudeKey = ""
    @State private var showClearCacheAlert = false
    
    @State private var selectedClaudeModel: String = ""
    @State private var customClaudeModel: String = ""

    init(onClearCache: (() -> Void)? = nil, updater: SPUUpdater? = nil) {
        self.onClearCache = onClearCache
        self.updater = updater
    }

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

                HStack {
                    TextField("Base URL", text: $preferences.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Reset to Default") {
                        preferences.openAIBaseURL = PreferencesService.defaultOpenAIBaseURL
                    }
                    .buttonStyle(.borderless)
                    .disabled(preferences.openAIBaseURL == PreferencesService.defaultOpenAIBaseURL)
                }

                HStack {
                    TextField("Model", text: $preferences.openAIModel)
                        .textFieldStyle(.roundedBorder)
                    Button("Reset to Default") {
                        preferences.openAIModel = PreferencesService.defaultOpenAIModel
                    }
                    .buttonStyle(.borderless)
                    .disabled(preferences.openAIModel == PreferencesService.defaultOpenAIModel)
                }
            } header: {
                Label("OpenAI Compatible", systemImage: "brain")
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

            if let updater = updater {
                Section {
                    UpdateSettingsView(updater: updater)
                } header: {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
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
        AboutView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadKeys() {
        deepLKey = keychainService.retrieve(for: .deepL) ?? ""
        googleKey = keychainService.retrieve(for: .google) ?? ""
        openAIKey = keychainService.retrieve(for: .openAI) ?? ""
        claudeKey = keychainService.retrieve(for: .claude) ?? ""
        
        // Initialize Claude model selection state
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

private struct UpdateSettingsView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Toggle("Automatically check for updates", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))

        Button("Check for Updates Now") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text("MangaTranslator")
                    .font(.title2.bold())
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("© 2026 Chun-Wei Liu. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 8)

            VStack(spacing: 12) {
                Link(destination: URL(string: "mailto:kevinxo328@gmail.com")!) {
                    Label("kevinxo328@gmail.com", systemImage: "envelope")
                }
                Link(destination: URL(string: "https://github.com/kevinxo328")!) {
                    Label("GitHub", systemImage: "link")
                }
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: 300)
    }
}
