import Foundation
import CoreGraphics
import AppKit

enum Language: String, CaseIterable, Identifiable, Codable {
    case ja = "ja"
    case en = "en"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ja: return "JA"
        case .en: return "EN"
        case .zhHant: return "ZH-TW"
        }
    }

    var visionLanguageCode: String { rawValue }
}

enum TranslationEngine: String, CaseIterable, Identifiable, Codable {
    case deepL = "deepl"
    case google = "google"
    case openAI = "openai"
    case githubCopilot = "github-copilot"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepL: return "DeepL"
        case .google: return "Google Translate"
        case .openAI: return "OpenAI Compatible"
        case .githubCopilot: return "GitHub Copilot"
        }
    }

    var isLLM: Bool {
        switch self {
        case .openAI, .githubCopilot: return true
        case .deepL, .google: return false
        }
    }
}

struct CopilotModel: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String?

    var displayLabel: String {
        guard let category else { return name }
        let label: String
        switch category {
        case "powerful":   label = "Premium"
        case "lightweight": label = "Lite"
        default:           label = "Standard"
        }
        return "\(name) (\(label))"
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
    var image: NSImage? = nil
    var imageHash: String? = nil
    var state: PageState = .pending
}

struct GlossaryTerm: Identifiable {
    let id: String
    let sourceTerm: String
    let targetTerm: String
    let autoDetected: Bool
}

struct Glossary: Identifiable {
    let id: String
    let name: String
}

struct TranslationContext {
    let glossaryTerms: [GlossaryTerm]
    let recentPageSummaries: [String]

    static let empty = TranslationContext(glossaryTerms: [], recentPageSummaries: [])
}

struct TranslationOutput {
    let bubbles: [TranslatedBubble]
    let detectedTerms: [GlossaryTerm]
}

protocol TranslationService {
    var engine: TranslationEngine { get }
    func translate(
        bubbles: [BubbleCluster],
        from source: Language,
        to target: Language,
        context: TranslationContext
    ) async throws -> TranslationOutput
}
