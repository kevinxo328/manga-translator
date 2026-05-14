import Foundation

#if arch(arm64)
@_implementationOnly import MLX

public func clearPaddleOCRMLXGPUCache() {
    MLX.GPU.clearCache()
}
#endif
