import Testing
@testable import MangaTranslator

@Suite("DeviceCapabilityService")
struct DeviceCapabilityServiceTests {

    // MARK: - Apple Silicon with 16GB RAM

    @Test("checkPaddleOCRCapability returns .supported for Apple Silicon with 16GB")
    func appleSilicon16GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: true, physicalMemoryGB: 16))
        #expect(service.checkPaddleOCRCapability() == .supported)
    }

    @Test("checkPaddleOCRCapability returns .supported for Apple Silicon with more than 16GB")
    func appleSilicon32GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: true, physicalMemoryGB: 32))
        #expect(service.checkPaddleOCRCapability() == .supported)
    }

    // MARK: - Apple Silicon with less than 16GB RAM

    @Test("checkPaddleOCRCapability returns .unsupported for Apple Silicon with 8GB")
    func appleSilicon8GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: true, physicalMemoryGB: 8))
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }

    @Test("checkPaddleOCRCapability returns .unsupported for Apple Silicon with 12GB")
    func appleSilicon12GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: true, physicalMemoryGB: 12))
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }

    // MARK: - Intel architecture

    @Test("checkPaddleOCRCapability returns .unsupported for Intel with 32GB")
    func intel32GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: false, physicalMemoryGB: 32))
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }

    @Test("checkPaddleOCRCapability returns .unsupported for Intel with 16GB")
    func intel16GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: false, physicalMemoryGB: 16))
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }

    // MARK: - Boundary: 0GB RAM

    @Test("checkPaddleOCRCapability returns .unsupported when physicalMemory reports 0GB")
    func appleSilicon0GBBoundary() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: true, physicalMemoryGB: 0))
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }

    // MARK: - Boundary: 1GB (below minimum threshold)

    @Test("checkPaddleOCRCapability returns .unsupported for Apple Silicon with 1GB")
    func appleSilicon1GB() {
        let service = DeviceCapabilityService(deviceInfo: MockDeviceInfo(isAppleSilicon: true, physicalMemoryGB: 1))
        #expect(service.checkPaddleOCRCapability() == .unsupported)
    }
}

// MARK: - Test Helpers

private struct MockDeviceInfo: DeviceInfoProviding {
    let isAppleSilicon: Bool
    let physicalMemoryGB: Int
}
