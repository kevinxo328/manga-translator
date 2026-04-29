import Testing
import Foundation
import Combine
@testable import MangaTranslator

// MARK: - Mock ModelDownloadServicing

@MainActor
private final class MockModelDownloadService: ModelDownloadServicing {
    @Published private(set) var state: ModelDownloadState
    @Published private(set) var paddleOCREnabled: Bool

    var isPaddleOCREnabled: Bool { state == .downloaded && paddleOCREnabled }
    var downloadCalled = false
    var cancelCalled = false
    var deleteCalled = false
    var setEnabledHistory: [Bool] = []
    var deleteThrows: Error? = nil

    var statePublisher: AnyPublisher<ModelDownloadState, Never> { $state.eraseToAnyPublisher() }
    var enabledPublisher: AnyPublisher<Bool, Never> { $paddleOCREnabled.eraseToAnyPublisher() }

    init(state: ModelDownloadState = .notDownloaded, enabled: Bool = false) {
        self.state = state
        self.paddleOCREnabled = enabled
    }

    func download() async { downloadCalled = true; state = .downloaded }
    func cancel() { cancelCalled = true; state = .notDownloaded }
    func delete() async throws {
        if let e = deleteThrows { throw e }
        deleteCalled = true
        paddleOCREnabled = false
        state = .notDownloaded
    }
    func setEnabled(_ enabled: Bool) {
        setEnabledHistory.append(enabled)
        guard !enabled || state == .downloaded else { return }
        paddleOCREnabled = enabled
    }
}

// MARK: - Mock DeviceCapabilityChecking

private final class MockCapabilityChecker: DeviceCapabilityChecking {
    let capability: PaddleOCRCapability
    init(_ capability: PaddleOCRCapability) { self.capability = capability }
    func checkPaddleOCRCapability() -> PaddleOCRCapability { capability }
}

// MARK: - Helpers

@MainActor
private func makeViewModel(
    capability: PaddleOCRCapability = .supported,
    state: ModelDownloadState = .notDownloaded,
    enabled: Bool = false
) -> (PaddleOCRSettingsViewModel, MockModelDownloadService) {
    let service = MockModelDownloadService(state: state, enabled: enabled)
    let vm = PaddleOCRSettingsViewModel(capability: capability, downloadService: service)
    return (vm, service)
}

// MARK: - Task 7.1: DeviceCapabilityService integration in Settings

@Suite("PaddleOCRSettings - Task 7.1: DeviceCapabilityService integration")
struct PaddleOCRSettingsCapabilityTests {

    @Test("shouldShowRAMWarning is false for .supported capability")
    @MainActor
    func noWarningForSupported() {
        let (vm, _) = makeViewModel(capability: .supported)
        #expect(vm.shouldShowRAMWarning == false)
        #expect(vm.ramWarningGB == nil)
    }

    @Test("shouldShowRAMWarning is true with ram=8 for .supportedWithWarning(ram:8)")
    @MainActor
    func warningShownFor8GB() {
        let (vm, _) = makeViewModel(capability: .supportedWithWarning(ram: 8))
        #expect(vm.shouldShowRAMWarning == true)
        #expect(vm.ramWarningGB == 8)
    }

    @Test("shouldShowRAMWarning is false for .unsupported (Intel equivalent)")
    @MainActor
    func noWarningForUnsupported() {
        let (vm, _) = makeViewModel(capability: .unsupported)
        #expect(vm.shouldShowRAMWarning == false)
        #expect(vm.ramWarningGB == nil)
    }

    @Test("Capability is .unsupported on Intel device info")
    func intelDeviceIsUnsupported() {
        struct IntelDeviceInfo: DeviceInfoProviding {
            var isAppleSilicon: Bool { false }
            var physicalMemoryGB: Int { 16 }
        }
        let service = DeviceCapabilityService(deviceInfo: IntelDeviceInfo())
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }

    @Test("Capability is .supported for 16GB Apple Silicon")
    func siliconWith16GBIsSupported() {
        struct SiliconDeviceInfo: DeviceInfoProviding {
            var isAppleSilicon: Bool { true }
            var physicalMemoryGB: Int { 16 }
        }
        let service = DeviceCapabilityService(deviceInfo: SiliconDeviceInfo())
        #expect(service.checkPaddleOCRCapability() == .supported)
    }

    @Test("Capability is .supportedWithWarning for 8GB Apple Silicon")
    func siliconWith8GBShowsWarning() {
        struct SiliconDeviceInfo: DeviceInfoProviding {
            var isAppleSilicon: Bool { true }
            var physicalMemoryGB: Int { 8 }
        }
        let service = DeviceCapabilityService(deviceInfo: SiliconDeviceInfo())
        #expect(service.checkPaddleOCRCapability() == .supportedWithWarning(ram: 8))
    }
}

// MARK: - Task 7.2: State-driven UI

@Suite("PaddleOCRSettings - Task 7.2: State-driven UI labels")
struct PaddleOCRSettingsStateDrivenUITests {

    @Test("notDownloaded state: downloadState is .notDownloaded")
    @MainActor
    func notDownloadedState() {
        let (vm, _) = makeViewModel(state: .notDownloaded)
        if case .notDownloaded = vm.downloadState { } else {
            Issue.record("Expected .notDownloaded, got \(vm.downloadState)")
        }
    }

    @Test("downloading state: downloadState exposes progress")
    @MainActor
    func downloadingStateShowsProgress() {
        let (vm, _) = makeViewModel(state: .downloading(progress: 0.5))
        if case .downloading(let p) = vm.downloadState {
            #expect(p == 0.5)
        } else {
            Issue.record("Expected .downloading, got \(vm.downloadState)")
        }
    }

    @Test("downloaded+enabled: isPaddleOCREnabled is true")
    @MainActor
    func downloadedEnabledState() {
        let (vm, _) = makeViewModel(state: .downloaded, enabled: true)
        #expect(vm.isPaddleOCREnabled == true)
        if case .downloaded = vm.downloadState { } else {
            Issue.record("Expected .downloaded, got \(vm.downloadState)")
        }
    }

    @Test("downloaded+disabled: isPaddleOCREnabled is false, state is .downloaded")
    @MainActor
    func downloadedDisabledState() {
        let (vm, _) = makeViewModel(state: .downloaded, enabled: false)
        #expect(vm.isPaddleOCREnabled == false)
        if case .downloaded = vm.downloadState { } else {
            Issue.record("Expected .downloaded, got \(vm.downloadState)")
        }
    }
}

// MARK: - Task 7.3: Delete confirmation

@Suite("PaddleOCRSettings - Task 7.3: Delete confirmation dialog")
struct PaddleOCRSettingsDeleteConfirmationTests {

    @Test("confirmDeleteModel sets showDeleteConfirmation to true")
    @MainActor
    func confirmDeleteSetsFlag() {
        let (vm, _) = makeViewModel(state: .downloaded)
        #expect(vm.showDeleteConfirmation == false)
        vm.confirmDeleteModel()
        #expect(vm.showDeleteConfirmation == true)
    }

    @Test("deleteModel calls delete() and resets showDeleteConfirmation")
    @MainActor
    func deleteModelCallsServiceAndResets() async {
        let (vm, service) = makeViewModel(state: .downloaded, enabled: true)
        vm.confirmDeleteModel()
        await vm.deleteModel()
        #expect(service.deleteCalled == true)
        #expect(vm.showDeleteConfirmation == false)
    }

    @Test("cancelDelete resets confirmation without calling delete()")
    @MainActor
    func cancelDeleteDoesNotCallService() {
        let (vm, service) = makeViewModel(state: .downloaded)
        vm.confirmDeleteModel()
        vm.cancelDelete()
        #expect(service.deleteCalled == false)
        #expect(vm.showDeleteConfirmation == false)
    }

    @Test("deleteModel transitions state to .notDownloaded")
    @MainActor
    func deleteModelResetsState() async {
        let (vm, service) = makeViewModel(state: .downloaded, enabled: true)
        await vm.deleteModel()
        if case .notDownloaded = service.state { } else {
            Issue.record("Expected .notDownloaded after delete, got \(service.state)")
        }
    }
}

// MARK: - Task 7.4: Preference persistence

@Suite("PaddleOCRSettings - Task 7.4: Preference persistence")
struct PaddleOCRSettingsPreferencePersistenceTests {

    @Test("setEnabled(true) writes enabled when model is downloaded")
    @MainActor
    func setEnabledTrueWhenDownloaded() {
        let (vm, service) = makeViewModel(state: .downloaded, enabled: false)
        vm.enablePaddleOCR()
        #expect(service.setEnabledHistory.contains(true))
        #expect(service.paddleOCREnabled == true)
    }

    @Test("disablePaddleOCR writes enabled=false")
    @MainActor
    func disablePaddleOCRWritesFalse() {
        let (vm, service) = makeViewModel(state: .downloaded, enabled: true)
        vm.disablePaddleOCR()
        #expect(service.setEnabledHistory.contains(false))
        #expect(service.paddleOCREnabled == false)
    }

    @Test("delete resets isPaddleOCREnabled to false")
    @MainActor
    func deleteResetsPaddleOCREnabled() async {
        let (vm, service) = makeViewModel(state: .downloaded, enabled: true)
        #expect(service.isPaddleOCREnabled == true)
        await vm.deleteModel()
        #expect(service.isPaddleOCREnabled == false)
    }
}

// MARK: - Task 7.4a: Enable gating

@Suite("PaddleOCRSettings - Task 7.4a: Enable gating")
struct PaddleOCRSettingsEnableGatingTests {

    @Test("enablePaddleOCR rejected when model is not downloaded")
    @MainActor
    func enableRejectedWhenNotDownloaded() {
        let (vm, service) = makeViewModel(state: .notDownloaded, enabled: false)
        vm.enablePaddleOCR()
        #expect(service.paddleOCREnabled == false,
                "paddleOCREnabled must remain false when model is not downloaded")
    }

    @Test("enablePaddleOCR allowed when model is downloaded")
    @MainActor
    func enableAllowedWhenDownloaded() {
        let (vm, service) = makeViewModel(state: .downloaded, enabled: false)
        vm.enablePaddleOCR()
        #expect(service.paddleOCREnabled == true)
    }

    @Test("isPaddleOCREnabled stays false after rejected enable attempt")
    @MainActor
    func isPaddleOCREnabledRemainsAfterRejection() {
        let (vm, service) = makeViewModel(state: .notDownloaded, enabled: false)
        vm.enablePaddleOCR()
        #expect(vm.isPaddleOCREnabled == false)
        #expect(service.isPaddleOCREnabled == false)
    }

    @Test("MockModelDownloadService setEnabled(true) ignored when not downloaded")
    @MainActor
    func serviceBlocksSetEnabledTrue() {
        let service = MockModelDownloadService(state: .notDownloaded, enabled: false)
        service.setEnabled(true)
        #expect(service.isPaddleOCREnabled == false)
    }
}

// MARK: - Task 7.5: Strict-mode error UX

@Suite("PaddleOCRSettings - Task 7.5: Strict-mode error UX")
struct PaddleOCRSettingsStrictModeErrorUXTests {

    @Test("inferenceFailed UI info has non-empty actionable text")
    func inferenceFailedIsActionable() {
        let info = PaddleOCRErrorUIMapping.uiInfo(for: .inferenceFailed("test"))
        #expect(!info.title.isEmpty)
        #expect(!info.message.isEmpty)
        #expect(!info.actionHints.isEmpty)
    }

    @Test("inferenceFailed message does not mention fallback was used")
    func inferenceFailedDoesNotMentionFallback() {
        let info = PaddleOCRErrorUIMapping.uiInfo(for: .inferenceFailed("test"))
        let combined = (info.title + info.message).lowercased()
        #expect(!combined.contains("fallback"), "Error message must not claim fallback OCR was used")
        #expect(!combined.contains("manga-ocr"), "Error message must not claim MangaOCR was used as fallback")
    }

    @Test("inferenceFailed actionHints include retry and settings guidance")
    func inferenceFailedHasRetryAndSettingsHints() {
        let info = PaddleOCRErrorUIMapping.uiInfo(for: .inferenceFailed("test"))
        let hintsLowercased = info.actionHints.map { $0.lowercased() }
        let hasRetry = hintsLowercased.contains(where: { $0.contains("retry") || $0.contains("try again") })
        let hasSettings = hintsLowercased.contains(where: { $0.contains("settings") || $0.contains("download") })
        #expect(hasRetry, "actionHints must include a retry option")
        #expect(hasSettings, "actionHints must include settings or re-download option")
    }

    @Test("modelUnavailable message guides user to download")
    func modelUnavailableGuideToDownload() {
        let info = PaddleOCRErrorUIMapping.uiInfo(for: .modelUnavailable)
        let combined = (info.title + info.message).lowercased()
        #expect(combined.contains("settings") || combined.contains("download"),
                "modelUnavailable message must guide user to Settings or download")
    }
}

// MARK: - Task 7.5b: UI mapping tests

@Suite("PaddleOCRSettings - Task 7.5b: UI mapping per error code")
struct PaddleOCRSettingsUIMappingTests {

    private let allErrors: [PaddleOCRError] = [
        .inferenceFailed("x"),
        .modelUnavailable,
        .downloadFailed("x"),
        .verifyFailed,
        .storageUnavailable("x"),
        .operationCancelled,
    ]

    @Test("All error codes map to non-empty title")
    func allErrorCodesHaveNonEmptyTitle() {
        for error in allErrors {
            let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
            #expect(!info.title.isEmpty, "\(error.code): title must not be empty")
        }
    }

    @Test("All error codes map to non-empty message")
    func allErrorCodesHaveNonEmptyMessage() {
        for error in allErrors {
            let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
            #expect(!info.message.isEmpty, "\(error.code): message must not be empty")
        }
    }

    @Test("Non-cancellation errors have at least one action hint")
    func nonCancellationErrorsHaveActionHints() {
        let errorsWithActions: [PaddleOCRError] = [
            .inferenceFailed("x"), .modelUnavailable, .downloadFailed("x"),
            .verifyFailed, .storageUnavailable("x"),
        ]
        for error in errorsWithActions {
            let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
            #expect(!info.actionHints.isEmpty, "\(error.code): must have at least one action hint")
        }
    }
}

// MARK: - Task 7.5c: Mapping-layer separation

@Suite("PaddleOCRSettings - Task 7.5c: Localization key vs error code separation")
struct PaddleOCRSettingsMappingLayerTests {

    private let allErrors: [PaddleOCRError] = [
        .inferenceFailed("x"), .modelUnavailable, .downloadFailed("x"),
        .verifyFailed, .storageUnavailable("x"), .operationCancelled,
    ]

    @Test("Localization key is distinct from error code")
    func localizationKeyDistinctFromErrorCode() {
        for error in allErrors {
            let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
            #expect(info.localizationKey != error.code,
                    "\(error.code): localizationKey must differ from error code")
        }
    }

    @Test("Localization key is not the error description")
    func localizationKeyNotErrorDescription() {
        for error in allErrors {
            let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
            let desc = error.errorDescription ?? ""
            #expect(info.localizationKey != desc,
                    "\(error.code): localizationKey must differ from errorDescription")
        }
    }

    @Test("Localization key uses 'error.paddleocr.' prefix convention")
    func localizationKeyUsesConvention() {
        for error in allErrors {
            let info = PaddleOCRErrorUIMapping.uiInfo(for: error)
            #expect(info.localizationKey.hasPrefix("error.paddleocr."),
                    "\(error.code): localizationKey must use 'error.paddleocr.' prefix")
        }
    }
}

// MARK: - Task 7.5a: Enable rejection messaging

@Suite("PaddleOCRSettings - Task 7.5a: Enable rejection messaging")
struct PaddleOCRSettingsEnableRejectionTests {

    @Test("enablePaddleOCR when not downloaded sets enableRejectionMessage")
    @MainActor
    func enableRejectionMessageSetWhenNotDownloaded() {
        let (vm, _) = makeViewModel(state: .notDownloaded)
        vm.enablePaddleOCR()
        #expect(vm.enableRejectionMessage != nil,
                "enableRejectionMessage must be set when model is not downloaded")
    }

    @Test("Rejection message contains download guidance")
    @MainActor
    func rejectionMessageContainsDownloadGuidance() {
        let (vm, _) = makeViewModel(state: .notDownloaded)
        vm.enablePaddleOCR()
        let message = vm.enableRejectionMessage?.lowercased() ?? ""
        #expect(message.contains("download"), "Rejection message must contain download guidance")
    }

    @Test("Toggle remains off (isPaddleOCREnabled false) after rejected enable")
    @MainActor
    func toggleRemainsOffAfterRejection() {
        let (vm, _) = makeViewModel(state: .notDownloaded)
        vm.enablePaddleOCR()
        #expect(vm.isPaddleOCREnabled == false,
                "isPaddleOCREnabled must remain false after rejected enable")
    }

    @Test("Successful enable clears rejection message")
    @MainActor
    func successfulEnableClearsRejectionMessage() {
        let (vm, _) = makeViewModel(state: .notDownloaded)
        vm.enablePaddleOCR() // sets message

        // Now simulate model downloaded and try again
        let (vm2, _) = makeViewModel(state: .downloaded)
        vm2.enablePaddleOCR()
        #expect(vm2.enableRejectionMessage == nil,
                "Rejection message must be nil after successful enable")
    }
}

// MARK: - Reactivity bug regression tests

@Suite("PaddleOCRSettings - Reactivity: ViewModel must publish changes when service state changes")
struct PaddleOCRSettingsReactivityTests {

    // Regression: Clicking Download was not updating the UI.
    // Root cause was that downloadState/isPaddleOCREnabled were plain computed properties;
    // the ViewModel never subscribed to the service so objectWillChange was never fired.
    // Fix: ViewModel now subscribes to objectWillChangePublisher and holds @Published copies.
    @Test("Regression: service state change fires vm.objectWillChange (clicking Download updates UI)")
    @MainActor
    func regressionServiceStateChangeFiresVMChange() async {
        let (vm, _) = makeViewModel(state: .notDownloaded)
        var changeCount = 0
        let cancellable = vm.objectWillChange.sink { _ in changeCount += 1 }
        defer { _ = cancellable }

        await vm.downloadModel()

        #expect(changeCount > 0,
                "ViewModel must publish objectWillChange when service state changes — clicking Download must update the UI")
    }

    @Test("ViewModel publishes objectWillChange when service state changes to .downloaded")
    @MainActor
    func viewModelPublishesOnDownloadComplete() async {
        let (vm, _) = makeViewModel(state: .notDownloaded)

        var changeCount = 0
        let cancellable = vm.objectWillChange.sink { _ in changeCount += 1 }
        defer { _ = cancellable }

        await vm.downloadModel()

        #expect(changeCount > 0,
                "ViewModel must publish objectWillChange when service state changes — clicking Download must update the UI")
    }

    @Test("ViewModel downloadState is .downloaded after downloadModel() completes and change is published")
    @MainActor
    func viewModelDownloadStateUpdatesAndPublishes() async {
        let (vm, _) = makeViewModel(state: .notDownloaded)

        // Use $downloadState (publishes new value) instead of objectWillChange (fires before change).
        var publishedStates: [ModelDownloadState] = []
        let cancellable = vm.$downloadState.sink { publishedStates.append($0) }
        defer { _ = cancellable }

        #expect(publishedStates == [.notDownloaded], "Initial state must be .notDownloaded")

        await vm.downloadModel()

        #expect(publishedStates.contains(.downloaded),
                "ViewModel must publish .downloaded state after download completes")
    }

    @Test("ViewModel publishes objectWillChange when enablePaddleOCR() changes enabled state")
    @MainActor
    func viewModelPublishesOnEnableChange() {
        let (vm, _) = makeViewModel(state: .downloaded, enabled: false)

        var changeCount = 0
        let cancellable = vm.objectWillChange.sink { _ in changeCount += 1 }
        defer { _ = cancellable }

        vm.enablePaddleOCR()

        #expect(changeCount > 0,
                "ViewModel must publish objectWillChange when paddleOCR is enabled — UI toggle must react")
        #expect(vm.isPaddleOCREnabled == true)
    }

    @Test("ViewModel publishes objectWillChange when disablePaddleOCR() is called")
    @MainActor
    func viewModelPublishesOnDisable() {
        let (vm, _) = makeViewModel(state: .downloaded, enabled: true)

        var changeCount = 0
        let cancellable = vm.objectWillChange.sink { _ in changeCount += 1 }
        defer { _ = cancellable }

        vm.disablePaddleOCR()

        #expect(changeCount > 0,
                "ViewModel must publish objectWillChange when paddleOCR is disabled")
        #expect(vm.isPaddleOCREnabled == false)
    }

    @Test("ViewModel publishes objectWillChange when cancelDownload() resets state")
    @MainActor
    func viewModelPublishesOnCancelDownload() {
        let (vm, _) = makeViewModel(state: .downloading(progress: 0.5))

        var changeCount = 0
        let cancellable = vm.objectWillChange.sink { _ in changeCount += 1 }
        defer { _ = cancellable }

        vm.cancelDownload()

        #expect(changeCount > 0,
                "ViewModel must publish objectWillChange when download is cancelled")
    }
}
