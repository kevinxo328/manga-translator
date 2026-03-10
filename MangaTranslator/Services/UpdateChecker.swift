import Sparkle

final class UpdateChecker: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater {
        updaterController.updater
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
