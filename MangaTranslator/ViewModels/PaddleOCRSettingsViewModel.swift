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

    var isCapabilitySupported: Bool {
        capability == .supported
    }

    // MARK: - Download actions

    func downloadModel() async {
        guard isCapabilitySupported else {
            enableRejectionMessage = "High-accuracy OCR requires Apple Silicon with at least 16GB unified memory."
            return
        }
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
        guard isCapabilitySupported else {
            enableRejectionMessage = "High-accuracy OCR requires Apple Silicon with at least 16GB unified memory."
            return
        }
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
