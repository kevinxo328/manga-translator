import SwiftUI
import Sparkle
import Combine

struct CheckForUpdatesView: View {
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        _checkForUpdatesViewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…", action: checkForUpdatesViewModel.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let checkForUpdatesAction: () -> Void
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        self.checkForUpdatesAction = updater.checkForUpdates
        self.canCheckForUpdates = updater.canCheckForUpdates
        self.cancellable = updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    init(
        canCheckForUpdatesPublisher: AnyPublisher<Bool, Never>,
        initialCanCheckForUpdates: Bool = false,
        checkForUpdatesAction: @escaping () -> Void = {}
    ) {
        self.checkForUpdatesAction = checkForUpdatesAction
        self.canCheckForUpdates = initialCanCheckForUpdates
        self.cancellable = canCheckForUpdatesPublisher
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func checkForUpdates() {
        checkForUpdatesAction()
    }
}
