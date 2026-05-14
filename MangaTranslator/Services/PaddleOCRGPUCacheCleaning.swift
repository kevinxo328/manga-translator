import Foundation

#if arch(arm64)
import MangaTranslatorMLX
#endif

protocol PaddleOCRGPUCacheCleaning: AnyObject, Sendable {
    func clearGPUCache()
}

final class NoOpPaddleOCRGPUCacheCleanup: PaddleOCRGPUCacheCleaning {
    func clearGPUCache() {}
}

#if arch(arm64)
final class MLXPaddleOCRGPUCacheCleanup: PaddleOCRGPUCacheCleaning {
    func clearGPUCache() {
        clearPaddleOCRMLXGPUCache()
    }
}
#endif
