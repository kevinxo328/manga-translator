import AppKit
import Sparkle

final class UpdateChecker: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private var lastCheckDate: Date?
    private let cooldown: TimeInterval = 3600 // 1 hour

    var updater: SPUUpdater {
        updaterController.updater
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        checkOnLaunch()
        startObservingFocus()
    }

    private func checkOnLaunch() {
        guard updater.automaticallyChecksForUpdates else { return }
        updater.checkForUpdatesInBackground()
        lastCheckDate = Date()
    }

    private func startObservingFocus() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        guard updater.automaticallyChecksForUpdates else { return }
        if let lastCheck = lastCheckDate, Date().timeIntervalSince(lastCheck) < cooldown {
            return
        }
        updater.checkForUpdatesInBackground()
        lastCheckDate = Date()
    }
}
