import SwiftUI
import Sparkle

enum ViewLayout {
    enum Settings {
        static let width: CGFloat = 600
        static let height: CGFloat = 650
    }
    enum MainWindow {
        static let minWidth: CGFloat = 800
        static let minHeight: CGFloat = 600
        static let imageColumnMinWidth: CGFloat = 500
    }
    enum Sidebar {
        static let minWidth: CGFloat = 300
        static let idealWidth: CGFloat = 350
    }
    enum About {
        static let width: CGFloat = 300
        static let windowHeight: CGFloat = 350
    }
}

/// Holds a strong reference to the About window so it can be reused on repeated clicks.
final class AppWindowHolder {
    var aboutWindow: NSWindow?
}

/// Replaces the `App > Settings…` menu item because we use a custom `Window` scene
/// (Settings scene silently ignores `.windowResizability`).
private struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

@main
struct MangaTranslatorApp: App {
    @StateObject private var preferences: PreferencesService
    @StateObject private var viewModel: TranslationViewModel
    private let updateChecker = UpdateChecker()
    private let windows = AppWindowHolder()

    init() {
        let prefs = PreferencesService()
        _preferences = StateObject(wrappedValue: prefs)
        _viewModel = StateObject(wrappedValue: TranslationViewModel(preferences: prefs))

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            DebugLogger.shared.flushSync()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .task {
                    #if arch(arm64)
                    await ModelDownloadService.shared.verifyOnLaunch()
                    #endif
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    viewModel.showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .appInfo) {
                Button("About MangaTranslator") {
                    if let existing = windows.aboutWindow {
                        existing.makeKeyAndOrderFront(nil)
                    } else {
                        let aboutWindow = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: ViewLayout.About.width, height: ViewLayout.About.windowHeight),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
                        aboutWindow.title = "About MangaTranslator"
                        aboutWindow.center()
                        aboutWindow.isReleasedWhenClosed = false
                        aboutWindow.contentView = NSHostingView(rootView: AboutView())
                        windows.aboutWindow = aboutWindow
                        aboutWindow.makeKeyAndOrderFront(nil)
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updateChecker.updater)
            }

            CommandGroup(after: .toolbar) {
                Toggle("Show Path Bar", isOn: $preferences.showPathBar)
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton()
            }
        }

        Window("Settings", id: "settings") {
            SettingsView(preferences: preferences, viewModel: viewModel, onClearCache: viewModel.clearCacheAndResetPages, onFetchCacheSize: viewModel.translationCacheSize, updater: updateChecker.updater)
        }
        .defaultSize(width: ViewLayout.Settings.width, height: ViewLayout.Settings.height)
        .windowResizability(.contentMinSize)
        .commandsRemoved()
    }
}
