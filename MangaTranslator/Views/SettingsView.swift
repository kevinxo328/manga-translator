import SwiftUI
import Sparkle

enum SettingsTab: Hashable, CaseIterable {
    case apiKeys, preferences, glossary, debug, about

    var label: String {
        switch self {
        case .apiKeys: return "API Keys"
        case .preferences: return "Preferences"
        case .debug: return "Debug"
        case .about: return "About"
        case .glossary: return "Glossary"
        }
    }

    var systemImage: String {
        switch self {
        case .apiKeys: return "key"
        case .preferences: return "gearshape"
        case .debug: return "ant"
        case .about: return "info.circle"
        case .glossary: return "text.book.closed"
        }
    }

    // Maps a string identifier to a SettingsTab. Unknown identifiers fall back to .apiKeys.
    static func from(identifier: String) -> SettingsTab {
        switch identifier {
        case "apiKeys": return .apiKeys
        case "preferences": return .preferences
        case "debug": return .debug
        case "about": return .about
        case "glossary": return .glossary
        default: return .apiKeys
        }
    }

    // The canonical string identifier for this tab (written back to activeTabIdentifier).
    var identifier: String {
        switch self {
        case .apiKeys: return "apiKeys"
        case .preferences: return "preferences"
        case .debug: return "debug"
        case .about: return "about"
        case .glossary: return "glossary"
        }
    }

    // Writes the canonical identifier back to preferences when the stored value is unknown.
    // Extracted as a static helper so unit tests can verify the write-back without a live view.
    static func normalizeIdentifier(in preferences: PreferencesService) {
        let tab = from(identifier: preferences.activeTabIdentifier)
        if tab.identifier != preferences.activeTabIdentifier {
            preferences.activeTabIdentifier = tab.identifier
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesService
    @ObservedObject var viewModel: TranslationViewModel
    private let keychainService = KeychainService()
    var onClearCache: (() -> Void)?
    var onFetchCacheSize: (() -> Int64)?
    private let updater: SPUUpdater?

    @State private var deepLKey = ""
    @State private var googleKey = ""
    @State private var openAIKey = ""
    @State private var showClearCacheAlert = false
    @State private var cacheSizeBytes: Int64 = 0
    @State private var copilotAvailability: CopilotAvailability = .notInstalled
    @State private var copilotModels: [CopilotModel] = []
    @State private var isLoadingCopilotModels = false

    #if arch(arm64)
    @StateObject private var paddleOCRViewModel: PaddleOCRSettingsViewModel = {
        let capability = DeviceCapabilityService.shared.checkPaddleOCRCapability()
        return PaddleOCRSettingsViewModel(
            capability: capability,
            downloadService: ModelDownloadService.shared
        )
    }()
    #endif

    init(
        preferences: PreferencesService,
        viewModel: TranslationViewModel,
        onClearCache: (() -> Void)? = nil,
        onFetchCacheSize: (() -> Int64)? = nil,
        updater: SPUUpdater? = nil
    ) {
        self.preferences = preferences
        self.viewModel = viewModel
        self.onClearCache = onClearCache
        self.onFetchCacheSize = onFetchCacheSize
        self.updater = updater
    }

    // Derived from preferences.activeTabIdentifier; unknown identifiers fall back to .apiKeys.
    // Manual tab selection writes the canonical identifier back to preferences so routing stays in sync.
    private var selectedTabBinding: Binding<SettingsTab> {
        Binding(
            get: {
                SettingsTab.from(identifier: preferences.activeTabIdentifier)
            },
            set: { newTab in
                preferences.activeTabIdentifier = newTab.identifier
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTabBinding) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selectedTabBinding.wrappedValue {
                case .apiKeys: apiKeysTab
                case .preferences: preferencesTab
                case .debug: debugTab
                case .about: aboutTab
                case .glossary: GlossaryView(viewModel: viewModel, isEmbedded: true)
                }
            }
            .navigationTitle(selectedTabBinding.wrappedValue.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: ViewLayout.Settings.width, minHeight: ViewLayout.Settings.height)
        .onAppear {
            loadKeys()
            normalizeActiveTabIdentifier()
        }
        .onChange(of: preferences.activeTabIdentifier) { _, _ in
            normalizeActiveTabIdentifier()
        }
        .task {
            copilotAvailability = CopilotEnvironment.check()
            if !copilotAvailability.isAvailable && preferences.translationEngine == .githubCopilot {
                preferences.translationEngine = .openAI
            }
            if case .available(let token) = copilotAvailability {
                isLoadingCopilotModels = true
                copilotModels = (try? await CopilotEnvironment.fetchModels(token: token)) ?? []
                isLoadingCopilotModels = false
            }
        }
    }

    private var baseURLValidationError: String? {
        do {
            try BaseURLValidator.validate(preferences.openAIBaseURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var apiKeysTab: some View {
        Form {
            Section {
                SecureField("API Key", text: $deepLKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: deepLKey) { _, newValue in
                        saveKey(newValue, for: .deepL)
                    }
            } header: {
                Label("DeepL", systemImage: "globe.europe.africa")
            }

            Section {
                SecureField("API Key", text: $googleKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: googleKey) { _, newValue in
                        saveKey(newValue, for: .google)
                    }
            } header: {
                Label("Google Translate", systemImage: "g.circle")
            }

            Section {
                SecureField("API Key", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: openAIKey) { _, newValue in
                        saveKey(newValue, for: .openAI)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Base URL", text: $preferences.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                        Button("Reset") {
                            preferences.openAIBaseURL = PreferencesService.defaultOpenAIBaseURL
                        }
                        .buttonStyle(.borderless)
                        .disabled(preferences.openAIBaseURL == PreferencesService.defaultOpenAIBaseURL)
                    }

                    if let error = baseURLValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    TextField("Model", text: $preferences.openAIModel)
                        .textFieldStyle(.roundedBorder)
                    Button("Reset") {
                        preferences.openAIModel = PreferencesService.defaultOpenAIModel
                    }
                    .buttonStyle(.borderless)
                    .disabled(preferences.openAIModel == PreferencesService.defaultOpenAIModel)
                }
            } header: {
                Label("OpenAI Compatible", systemImage: "brain")
            }

            Section {
                switch copilotAvailability {
                case .available:
                    Label("Copilot CLI detected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if isLoadingCopilotModels {
                        ProgressView()
                    } else if copilotModels.isEmpty {
                        Text("No models available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Model", selection: $preferences.copilotModel) {
                            ForEach(copilotModels) { model in
                                Text(model.displayLabel).tag(model.id)
                            }
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
        }
        .formStyle(.grouped)
        .padding()
    }

    private var preferencesTab: some View {
        Form {
            Section {
                Picker("Source Language", selection: $preferences.sourceLanguage) {
                    ForEach(Language.sourceLanguages) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Picker("Target Language", selection: $preferences.targetLanguage) {
                    ForEach(Language.targetLanguages) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Picker("Translation Engine", selection: $preferences.translationEngine) {
                    ForEach(TranslationEngine.allCases.filter {
                        $0 != .githubCopilot || copilotAvailability.isAvailable
                    }) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
            } header: {
                Label("Translation Defaults", systemImage: "gear")
            }

            #if arch(arm64)
            PaddleOCRSettingsSection(viewModel: paddleOCRViewModel)
            #endif

            if let updater = updater {
                Section {
                    UpdateSettingsView(updater: updater)
                } header: {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            if onClearCache != nil {
                Section {
                    LabeledContent("Cache Size") {
                        Text(ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        showClearCacheAlert = true
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                } header: {
                    Label("Cache", systemImage: "internaldrive")
                } footer: {
                    Text("Removes all cached translations. Pages will be re-translated on next run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    cacheSizeBytes = onFetchCacheSize?() ?? 0
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Clear Cache", isPresented: $showClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                onClearCache?()
                cacheSizeBytes = 0
            }
        } message: {
            Text("This will delete all cached translation results. This action cannot be undone.")
        }
    }

    private var debugTab: some View {
        DebugLogView()
    }

    private var aboutTab: some View {
        AboutView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func normalizeActiveTabIdentifier() {
        SettingsTab.normalizeIdentifier(in: preferences)
    }

    private func loadKeys() {
        deepLKey = keychainService.retrieve(for: .deepL) ?? ""
        googleKey = keychainService.retrieve(for: .google) ?? ""
        openAIKey = keychainService.retrieve(for: .openAI) ?? ""
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
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _checkForUpdatesViewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Toggle("Automatically check for updates", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))

        Button("Check for Updates Now") {
            checkForUpdatesViewModel.checkForUpdates()
        }
        .controlSize(.small)
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct AboutView: View {
    private static let info = Bundle.main.infoDictionary

    private var version: String {
        Self.info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var copyright: String {
        Self.info?["NSHumanReadableCopyright"] as? String ?? ""
    }
    private var contactEmail: String? {
        Self.info?["AppContactEmail"] as? String
    }
    private var githubURL: URL? {
        (Self.info?["AppGitHubURL"] as? String).flatMap(URL.init)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text("MangaTranslator")
                    .font(.title2.bold())

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 8)

            VStack(spacing: 12) {
                if let email = contactEmail {
                    Link(destination: URL(string: "mailto:\(email)")!) {
                        Label(email, systemImage: "envelope")
                    }
                }
                if let url = githubURL {
                    Link(destination: url) {
                        Label("GitHub", systemImage: "link")
                    }
                }
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: ViewLayout.About.width)
    }
}
