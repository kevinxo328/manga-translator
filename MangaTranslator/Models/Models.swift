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
        case .ja: return "🇯🇵 Japanese"
        case .en: return "🇺🇸 English"
        case .zhHant: return "🇹🇼 Traditional Chinese"
        }
    }

    // OCR currently supports Japanese and English as source languages only.
    static let sourceLanguages: [Language] = [.ja, .en]

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
    var isInverted: Bool = false
}

struct MangaOCRPageResult {
    let bubbles: [BubbleCluster]
    let textPixelMask: CGImage?
    let lowConfidenceDetectionCount: Int
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
    var textPixelMask: CGImage? = nil
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

extension [TranslatedBubble] {
    var sortedByIndex: [TranslatedBubble] {
        sorted { $0.index < $1.index }
    }
}

struct BatchPageInput {
    let pageId: String
    let bubbles: [BubbleCluster]
}

struct BatchPageOutput {
    let pageId: String
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

    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput]
}

extension TranslationService {
    // Default fallback used by engines that have not opted in to true multi-page batching
    // (DeepL, Google) and by test fakes that only implement the per-page method. The batch
    // scheduler may still route through this path; behaviour matches today's per-page loop.
    func translateBatch(
        pageInputs: [BatchPageInput],
        from source: Language,
        to target: Language,
        priorContext: TranslationContext
    ) async throws -> [BatchPageOutput] {
        var outputs: [BatchPageOutput] = []
        outputs.reserveCapacity(pageInputs.count)
        for input in pageInputs {
            let output = try await translate(
                bubbles: input.bubbles,
                from: source,
                to: target,
                context: priorContext
            )
            outputs.append(BatchPageOutput(
                pageId: input.pageId,
                bubbles: output.bubbles,
                detectedTerms: output.detectedTerms
            ))
        }
        return outputs
    }
}
