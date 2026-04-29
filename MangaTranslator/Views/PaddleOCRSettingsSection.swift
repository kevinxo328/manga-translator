import SwiftUI

#if arch(arm64)

struct PaddleOCRSettingsSection: View {
    @ObservedObject var viewModel: PaddleOCRSettingsViewModel

    var body: some View {
        Section {
            content
        } header: {
            Label("High-Accuracy OCR (PaddleOCR)", systemImage: "wand.and.stars")
        } footer: {
            if viewModel.shouldShowRAMWarning, let ram = viewModel.ramWarningGB {
                Text("Your Mac has \(ram)GB RAM. High-accuracy OCR may impact performance on other apps.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .confirmationDialog(
            "Delete Model Data",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteModel() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text("This will remove the downloaded high-accuracy OCR model. You can re-download it later.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            notDownloadedView
        case .downloading(let progress):
            downloadingView(progress: progress)
        case .downloaded:
            downloadedView
        case .failed(let error):
            failedView(error: error)
        }
    }

    private var notDownloadedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download the ~1GB model to enable higher-accuracy Japanese OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = viewModel.enableRejectionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Download and Enable") {
                Task { await viewModel.downloadModel() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress) {
                Text("Downloading model… \(Int(progress * 100))%")
                    .font(.caption)
            }

            Button("Cancel") {
                viewModel.cancelDownload()
            }
            .controlSize(.small)
        }
    }

    private var downloadedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isPaddleOCREnabled {
                Label("High-Accuracy OCR Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)

                HStack(spacing: 8) {
                    Button("Disable") {
                        viewModel.disablePaddleOCR()
                    }
                    .controlSize(.small)

                    Button("Delete Model Data", role: .destructive) {
                        viewModel.confirmDeleteModel()
                    }
                    .controlSize(.small)
                }
            } else {
                Label("High-Accuracy OCR Disabled", systemImage: "circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                if let message = viewModel.enableRejectionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 8) {
                    Button("Enable") {
                        viewModel.enablePaddleOCR()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Delete Model Data", role: .destructive) {
                        viewModel.confirmDeleteModel()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func failedView(error: PaddleOCRError) -> some View {
        let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
        return VStack(alignment: .leading, spacing: 8) {
            Label(info.title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
            Text(info.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await viewModel.downloadModel() }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Previews

#Preview("Not Downloaded") {
    let service = ModelDownloadService(configuration: .previewNotDownloaded)
    let vm = PaddleOCRSettingsViewModel(
        capability: .supported,
        downloadService: service
    )
    return Form {
        PaddleOCRSettingsSection(viewModel: vm)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 450)
}

#Preview("Downloading") {
    let service = ModelDownloadService(configuration: .previewDownloading)
    let vm = PaddleOCRSettingsViewModel(
        capability: .supported,
        downloadService: service
    )
    return Form {
        PaddleOCRSettingsSection(viewModel: vm)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 450)
}

#Preview("Downloaded + Enabled") {
    let service = ModelDownloadService(configuration: .previewDownloadedEnabled)
    let vm = PaddleOCRSettingsViewModel(
        capability: .supported,
        downloadService: service
    )
    return Form {
        PaddleOCRSettingsSection(viewModel: vm)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 450)
}

#Preview("Downloaded + Disabled") {
    let service = ModelDownloadService(configuration: .previewDownloadedDisabled)
    let vm = PaddleOCRSettingsViewModel(
        capability: .supported,
        downloadService: service
    )
    return Form {
        PaddleOCRSettingsSection(viewModel: vm)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 450)
}

#Preview("Downloading + 8GB Warning") {
    let service = ModelDownloadService(configuration: .previewDownloading)
    let vm = PaddleOCRSettingsViewModel(
        capability: .supportedWithWarning(ram: 8),
        downloadService: service
    )
    return Form {
        PaddleOCRSettingsSection(viewModel: vm)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 450)
}

#endif
