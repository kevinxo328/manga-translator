import Foundation

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to create CGImage from input"
        }
    }
}
