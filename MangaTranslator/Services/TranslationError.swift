import Foundation

enum TranslationError: LocalizedError {
    case missingAPIKey(TranslationEngine)
    case chatGPTPlanNotConnected
    case chatGPTPlanModelNotSelected
    case invalidResponse
    case apiError(SanitizedAPIError)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let engine):
            return "API key not found for \(engine.displayName). Please add it in Settings."
        case .chatGPTPlanNotConnected:
            return "ChatGPT Plan is not connected. Sign in from Settings to translate."
        case .chatGPTPlanModelNotSelected:
            return "Choose an available ChatGPT Plan model in Settings before translating."
        case .invalidResponse:
            return "Failed to parse translation response"
        case .apiError(let sanitized):
            return sanitized.localizedSummary
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
