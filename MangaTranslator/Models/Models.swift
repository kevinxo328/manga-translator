import Foundation
import CoreGraphics

enum Language: String, CaseIterable, Identifiable, Codable {
    case ja = "ja"
    case en = "en"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ja: return "Japanese"
        case .en: return "English"
        case .zhHant: return "Traditional Chinese"
        }
    }

    var visionLanguageCode: String { rawValue }
}

enum TranslationEngine: String, CaseIterable, Identifiable, Codable {
    case deepL = "deepl"
    case google = "google"
    case openAI = "openai"
    case claude = "claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepL: return "DeepL"
        case .google: return "Google Translate"
        case .openAI: return "OpenAI"
        case .claude: return "Claude"
        }
    }

    var isLLM: Bool {
        switch self {
        case .openAI, .claude: return true
        case .deepL, .google: return false
        }
    }
}

struct LLMModel: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let apiIdentifier: String
    
    init(displayName: String, apiIdentifier: String) {
        self.id = apiIdentifier
        self.displayName = displayName
        self.apiIdentifier = apiIdentifier
    }
}

extension TranslationEngine {
    static let openAIModels = [
        LLMModel(displayName: "GPT-5 Turbo", apiIdentifier: "gpt-5-turbo"),
        LLMModel(displayName: "GPT-5", apiIdentifier: "gpt-5")
    ]
    
    static let claudeModels = [
        LLMModel(displayName: "Claude Sonnet 4.5", apiIdentifier: "claude-sonnet-4-5-20250929"),
        LLMModel(displayName: "Claude Haiku 3.5", apiIdentifier: "claude-3-5-haiku-20241022")
    ]
}

struct TextObservation: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let text: String
    let confidence: Float
}

struct BubbleCluster: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let text: String
    let observations: [TextObservation]
    var index: Int = 0
}

struct TranslatedBubble: Identifiable {
    let id = UUID()
    let bubble: BubbleCluster
    let translatedText: String
    let index: Int
}

enum PageState {
    case pending
    case processing
    case translated([TranslatedBubble])
    case error(String)
}

struct MangaPage: Identifiable {
    let id = UUID()
    let imageURL: URL
    var state: PageState = .pending
}

protocol TranslationService {
    var engine: TranslationEngine { get }
    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language
    ) async throws -> [TranslatedBubble]
}
