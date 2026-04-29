import Foundation

struct PaddleOCRErrorUIInfo {
    let title: String
    let message: String
    let actionHints: [String]
    // UI localization key — explicitly separate from PaddleOCRError.code
    let localizationKey: String
}

enum PaddleOCRErrorUIMapping {
    static func uiInfo(for error: PaddleOCRError) -> PaddleOCRErrorUIInfo {
        switch error {
        case .inferenceFailed:
            return PaddleOCRErrorUIInfo(
                title: "High-Accuracy OCR Failed",
                message: "Text recognition failed. Please try again or go to Settings to re-download the model.",
                actionHints: ["Retry", "Go to Settings", "Re-download model"],
                localizationKey: "error.paddleocr.inference_failed"
            )
        case .modelUnavailable:
            return PaddleOCRErrorUIInfo(
                title: "Model Unavailable",
                message: "The high-accuracy OCR model is not installed. Please download it in Settings.",
                actionHints: ["Go to Settings", "Re-download model"],
                localizationKey: "error.paddleocr.model_unavailable"
            )
        case .downloadFailed:
            return PaddleOCRErrorUIInfo(
                title: "Download Failed",
                message: "Failed to download the OCR model. Check your internet connection and try again.",
                actionHints: ["Retry download"],
                localizationKey: "error.paddleocr.download_failed"
            )
        case .verifyFailed:
            return PaddleOCRErrorUIInfo(
                title: "Verification Failed",
                message: "The downloaded model is corrupted. Please re-download it.",
                actionHints: ["Re-download model"],
                localizationKey: "error.paddleocr.verify_failed"
            )
        case .storageUnavailable:
            return PaddleOCRErrorUIInfo(
                title: "Storage Unavailable",
                message: "Not enough disk space to download the OCR model. Free up space and try again.",
                actionHints: ["Free up disk space", "Try again"],
                localizationKey: "error.paddleocr.storage_unavailable"
            )
        case .operationCancelled:
            return PaddleOCRErrorUIInfo(
                title: "Cancelled",
                message: "The operation was cancelled.",
                actionHints: [],
                localizationKey: "error.paddleocr.operation_cancelled"
            )
        }
    }
}
