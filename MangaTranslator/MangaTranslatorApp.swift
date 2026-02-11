import SwiftUI
import Sparkle

@main
struct MangaTranslatorApp: App {
    @StateObject private var viewModel = TranslationViewModel()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MangaTranslator") {
                    let aboutWindow = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 300, height: 350),
                        styleMask: [.titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
                    aboutWindow.title = "About MangaTranslator"
                    aboutWindow.center()
                    aboutWindow.isReleasedWhenClosed = false
                    aboutWindow.contentView = NSHostingView(rootView: AboutView())
                    aboutWindow.makeKeyAndOrderFront(nil)
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView(onClearCache: viewModel.clearCacheAndResetPages, updater: updaterController.updater)
        }
    }
}
