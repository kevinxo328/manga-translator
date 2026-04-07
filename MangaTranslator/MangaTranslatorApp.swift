import SwiftUI
import Sparkle

/// Holds a strong reference to the About window so it can be reused on repeated clicks.
final class AppWindowHolder {
    var aboutWindow: NSWindow?
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MangaTranslator") {
                    if let existing = windows.aboutWindow {
                        existing.makeKeyAndOrderFront(nil)
                    } else {
                        let aboutWindow = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: 300, height: 350),
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
        }

        Settings {
            SettingsView(preferences: preferences, onClearCache: viewModel.clearCacheAndResetPages, updater: updateChecker.updater)
        }
    }
}
