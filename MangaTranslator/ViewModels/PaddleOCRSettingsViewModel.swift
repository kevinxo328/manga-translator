import Foundation
import Combine

@MainActor
final class PaddleOCRSettingsViewModel: ObservableObject {
    let capability: PaddleOCRCapability
    let downloadService: any ModelDownloadServicing

    @Published private(set) var downloadState: ModelDownloadState
    @Published private(set) var isPaddleOCREnabled: Bool
    @Published var showDeleteConfirmation = false
    @Published var enableRejectionMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()

    init(
        capability: PaddleOCRCapability,
        downloadService: any ModelDownloadServicing
    ) {
        self.capability = capability
        self.downloadService = downloadService
        self.downloadState = downloadService.state
        self.isPaddleOCREnabled = downloadService.isPaddleOCREnabled

        // Use typed publishers so we receive the NEW value rather than reading
        // the service during willSet (which would return the stale old value).
        Publishers.CombineLatest(
            downloadService.statePublisher,
            downloadService.enabledPublisher
        )
        .sink { [weak self] newState, newEnabled in
            guard let self else { return }
            self.downloadState = newState
            self.isPaddleOCREnabled = newState == .downloaded && newEnabled
        }
        .store(in: &cancellables)
    }

    // MARK: - Capability properties for view binding

    var shouldShowRAMWarning: Bool {
        if case .supportedWithWarning = capability { return true }
        return false
    }

    var ramWarningGB: Int? {
        if case .supportedWithWarning(let ram) = capability { return ram }
        return nil
    }

    // MARK: - Download actions

    func downloadModel() async {
        await downloadService.download()
    }

    func cancelDownload() {
        downloadService.cancel()
    }

    // MARK: - Delete actions

    func confirmDeleteModel() {
        showDeleteConfirmation = true
    }

    func deleteModel() async {
        try? await downloadService.delete()
        enableRejectionMessage = nil
        showDeleteConfirmation = false
    }

    func cancelDelete() {
        showDeleteConfirmation = false
    }

    // MARK: - Enable/disable actions

    func enablePaddleOCR() {
        guard downloadService.state == .downloaded else {
            enableRejectionMessage = "Download model first to use high-accuracy OCR."
            return
        }
        downloadService.setEnabled(true)
        enableRejectionMessage = nil
    }

    func disablePaddleOCR() {
        downloadService.setEnabled(false)
        enableRejectionMessage = nil
    }
}
