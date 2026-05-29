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
    let id: UUID
    // Mutable so Edit Mode's Move / Resize gestures can update geometry in
    // place on the working copy. Outside Edit Mode the field is treated as
    // immutable by convention; the OCR + translation pipeline constructs new
    // BubbleCluster values rather than mutating existing ones.
    var boundingBox: CGRect
    // Mutable so the Edit Mode commit pipeline can merge fresh OCR text into
    // an existing bubble via `withText(_:)`. Treated as immutable everywhere
    // else: OCR text is set at construction and replaced only on commit.
    var text: String
    let observations: [TextObservation]
    var index: Int = 0
    var isInverted: Bool = false
    // Tracks whether the user has touched this bubble's geometry in any Edit
    // Mode session — either by drawing it, moving it, or resizing it.
    // Single-bit semantics; sticky once set. See
    // `openspec/changes/manual-bubble-editing/design.md` §D5: the inverse of
    // a Move / Resize restores boundingBox only, never `isManual`. Cancel can
    // restore the pre-session value because Cancel restores the entire
    // snapshot, not because the flag is reset directly. Future "re-detect"
    // flows MUST consult this flag to decide which boxes to preserve.
    var isManual: Bool = false

    // Explicit initializer with `id` as a defaulted parameter so callers can
    // either let one be generated or supply an existing id (used by
    // `withText(_:)` and by the cache decoder where bubble identity is
    // re-minted on each read).
    init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        text: String,
        observations: [TextObservation],
        index: Int = 0,
        isInverted: Bool = false,
        isManual: Bool = false
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.text = text
        self.observations = observations
        self.index = index
        self.isInverted = isInverted
        self.isManual = isManual
    }

    // Convenience copy-with helper used by the Edit Mode commit pipeline when
    // merging fresh OCR text into an existing geometry. Returns a new value
    // with the same id, boundingBox, observations, index, isInverted, and
    // isManual but with a replaced `text`.
    func withText(_ newText: String) -> BubbleCluster {
        var copy = self
        copy.text = newText
        return copy
    }
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

// MARK: - Edit Mode

// Reversible user actions in an Edit Mode session. Pushed onto an EditSession's
// undo stack on first application; popped and inverted by `Cmd+Z`; re-applied
// by `Cmd+Shift+Z`. See `openspec/changes/manual-bubble-editing/design.md` §D2
// for the apply / inverse table.
//
// `.delete` and `.unstageDelete` are set-based and idempotent on the session's
// `deletedBubbleIds` set: applying either twice has the same effect as once.
// This guarantees safe convergence when an `.unstageDelete` partially un-stages
// a member of an earlier `.multi([.delete, ...])` and the user later cycles
// through Cmd+Z / Cmd+Shift+Z.
//
// `.multi.inverse` MUST reverse its sub-inverses in opposite order so nested
// mutations unwind correctly.
indirect enum EditAction {
    case add(BubbleCluster)
    case delete(BubbleCluster)
    case unstageDelete(BubbleCluster)
    case move(id: UUID, from: CGRect, to: CGRect)
    case resize(id: UUID, from: CGRect, to: CGRect)
    case reorder(from: [UUID], to: [UUID])
    case multi([EditAction])
}

// Transactional, per-page edit state. Lives on TranslationViewModel as a
// private @MainActor property. See
// `openspec/changes/manual-bubble-editing/design.md` §D1.
//
// `dirtyBubbleIds` is a UI-only cache for rendering the sidebar's "已修改"
// dirty visuals during the in-progress session. The commit pipeline derives
// OCR-dirty classification from current `boundingBox` vs. originalSnapshot
// `boundingBox` (§D3), NOT from this set; drift in `dirtyBubbleIds` affects
// only UI badges, never OCR cost or correctness.
//
// `originalPageState` is the PageState at session open (always `.translated`
// per the gating rule). On Cancel the page state is restored to this value
// — including the case where an in-session Commit previously failed and left
// the page in `.error`. Cancel clears that error.
struct EditSession {
    let pageId: UUID
    var workingBubbles: [BubbleCluster]
    var dirtyBubbleIds: Set<UUID>
    var deletedBubbleIds: Set<UUID>
    var selectedBubbleIds: Set<UUID>
    var undoStack: [EditAction]
    var redoStack: [EditAction]
    let originalSnapshot: [TranslatedBubble]
    let originalPageState: PageState

    init(
        pageId: UUID,
        workingBubbles: [BubbleCluster],
        originalSnapshot: [TranslatedBubble],
        originalPageState: PageState,
        dirtyBubbleIds: Set<UUID> = [],
        deletedBubbleIds: Set<UUID> = [],
        selectedBubbleIds: Set<UUID> = [],
        undoStack: [EditAction] = [],
        redoStack: [EditAction] = []
    ) {
        self.pageId = pageId
        self.workingBubbles = workingBubbles
        self.dirtyBubbleIds = dirtyBubbleIds
        self.deletedBubbleIds = deletedBubbleIds
        self.selectedBubbleIds = selectedBubbleIds
        self.undoStack = undoStack
        self.redoStack = redoStack
        self.originalSnapshot = originalSnapshot
        self.originalPageState = originalPageState
    }
}

extension EditAction {
    // Reverses the visible effect of this action on `session`. See
    // `openspec/changes/manual-bubble-editing/design.md` §D2 for the full
    // table.
    //
    // - `.move` / `.resize` inverse restores `boundingBox` only; `isManual`
    //   stays sticky (§D5).
    // - `.delete` / `.unstageDelete` inverses are set operations on
    //   `deletedBubbleIds` and are idempotent.
    // - `.multi` inverts its sub-actions in reverse order.
    func applyInverse(to session: inout EditSession) {
        switch self {
        case .add(let bubble):
            session.workingBubbles.removeAll { $0.id == bubble.id }
            session.deletedBubbleIds.remove(bubble.id)
            session.dirtyBubbleIds.remove(bubble.id)
            session.selectedBubbleIds.remove(bubble.id)
            EditAction.redensifyIndices(&session.workingBubbles)
        case .delete(let bubble):
            session.deletedBubbleIds.remove(bubble.id)
        case .unstageDelete(let bubble):
            session.deletedBubbleIds.insert(bubble.id)
        case .move(let id, let from, _), .resize(let id, let from, _):
            if let idx = session.workingBubbles.firstIndex(where: { $0.id == id }) {
                session.workingBubbles[idx].boundingBox = from
                // isManual intentionally NOT restored — sticky flag, §D5.

                // Best-effort UI cleanup: when undo restores `boundingBox`
                // to the snapshot's value, drop the dirty badge so the
                // sidebar reflects "current geometry == snapshot" again.
                // Commit correctness does NOT depend on this — the commit
                // pipeline derives OCR-dirty from geometry-vs-snapshot
                // directly (§D3); this branch only keeps the in-session
                // visual in sync.
                if let snapshot = session.originalSnapshot.first(where: { $0.bubble.id == id }),
                   snapshot.bubble.boundingBox == from {
                    session.dirtyBubbleIds.remove(id)
                }
            }
        case .reorder(let from, _):
            session.workingBubbles = EditAction.reorder(session.workingBubbles, byIds: from)
            EditAction.redensifyIndices(&session.workingBubbles)
        case .multi(let actions):
            for action in actions.reversed() {
                action.applyInverse(to: &session)
            }
        }
    }

    // Rewrites every entry's `index` to its current array position (0..<n).
    // Used after any reorder / insert / remove so downstream consumers see a
    // dense reading order.
    static func redensifyIndices(_ bubbles: inout [BubbleCluster]) {
        for i in bubbles.indices {
            bubbles[i].index = i
        }
    }

    // Returns `bubbles` reordered so its elements appear in the order given
    // by `ids`. Ids not present in `bubbles` are ignored; bubbles whose id
    // is not in `ids` are dropped — callers should pass an `ids` array that
    // covers every bubble in `bubbles`.
    static func reorder(_ bubbles: [BubbleCluster], byIds ids: [UUID]) -> [BubbleCluster] {
        var byId = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.id, $0) })
        return ids.compactMap { byId.removeValue(forKey: $0) }
    }
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
