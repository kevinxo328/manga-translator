import Foundation

enum PaddleOCRError: Error, Equatable {
    case downloadFailed(String)
    case verifyFailed
    case modelUnavailable
    case inferenceFailed(String)
    case storageUnavailable(String)
    case operationCancelled

    // Stable contract key — never use directly as localization key
    var code: String {
        switch self {
        case .downloadFailed:      return "paddleocr.download_failed"
        case .verifyFailed:        return "paddleocr.verify_failed"
        case .modelUnavailable:    return "paddleocr.model_unavailable"
        case .inferenceFailed:     return "paddleocr.inference_failed"
        case .storageUnavailable:  return "paddleocr.storage_unavailable"
        case .operationCancelled:  return "paddleocr.operation_cancelled"
        }
    }
}

extension PaddleOCRError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg):      return "Download failed: \(msg)"
        case .verifyFailed:                 return "Checksum verification failed. Please try downloading again."
        case .modelUnavailable:             return "High-accuracy model is unavailable. Please download it in Settings."
        case .inferenceFailed(let msg):     return "OCR inference failed: \(msg)"
        case .storageUnavailable(let msg):  return "Storage unavailable: \(msg)"
        case .operationCancelled:           return "Operation was cancelled."
        }
    }
}

enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(PaddleOCRError)
}
