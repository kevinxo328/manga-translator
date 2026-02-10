import Foundation

enum TranslationError: LocalizedError {
    case missingAPIKey(TranslationEngine)
    case invalidResponse
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let engine):
            return "API key not found for \(engine.displayName). Please add it in Settings."
        case .invalidResponse:
            return "Failed to parse translation response"
        case .apiError(let message):
            return "API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
