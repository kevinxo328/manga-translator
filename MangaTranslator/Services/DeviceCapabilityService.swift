import Foundation

enum PaddleOCRCapability: Equatable {
    case supported
    case supportedWithWarning(ram: Int)
    case unsupported
}

protocol DeviceInfoProviding {
    var isAppleSilicon: Bool { get }
    var physicalMemoryGB: Int { get }
}

struct SystemDeviceInfo: DeviceInfoProviding {
    var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    var physicalMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }
}

protocol DeviceCapabilityChecking {
    func checkPaddleOCRCapability() -> PaddleOCRCapability
}

struct DeviceCapabilityService: DeviceCapabilityChecking {
    static let shared = DeviceCapabilityService()

    private let deviceInfo: DeviceInfoProviding

    init(deviceInfo: DeviceInfoProviding = SystemDeviceInfo()) {
        self.deviceInfo = deviceInfo
    }

    func checkPaddleOCRCapability() -> PaddleOCRCapability {
        guard deviceInfo.isAppleSilicon else { return .unsupported }
        let ram = deviceInfo.physicalMemoryGB
        guard ram > 0 else { return .unsupported }
        if ram >= 16 {
            return .supported
        } else {
            return .supportedWithWarning(ram: ram)
        }
    }
}
