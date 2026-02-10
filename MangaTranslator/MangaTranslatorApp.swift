import SwiftUI

@main
struct MangaTranslatorApp: App {
    @StateObject private var viewModel = TranslationViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView(onClearCache: viewModel.clearCacheAndResetPages)
        }
    }
}
