import Foundation

#if arch(arm64)
internal import MLX

public func clearPaddleOCRMLXGPUCache() {
    MLX.GPU.clearCache()
}
#endif
