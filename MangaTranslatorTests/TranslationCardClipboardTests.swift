import Testing
import CoreGraphics
@testable import MangaTranslator

// MARK: - Test Double

final class FakeClipboard: ClipboardWriting {
    var lastWritten: String?
    var shouldSucceed: Bool = true

    func write(_ string: String) -> Bool {
        lastWritten = string
        return shouldSucceed
    }
}

// MARK: - Helpers

private func makeBubble(text: String = "OCR text", translated: String = "Translated text") -> TranslatedBubble {
    let cluster = BubbleCluster(
        boundingBox: CGRect(x: 0, y: 0, width: 100, height: 50),
        text: text,
        observations: []
    )
    return TranslatedBubble(bubble: cluster, translatedText: translated, index: 0)
}

// MARK: - Tests

@Suite("TranslationCard clipboard actions")
struct TranslationCardClipboardTests {

    @Test("Copy Translation writes translatedText to clipboard")
    func copyTranslationWritesTranslatedText() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(text: "原文", translated: "Translated")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyTranslation()

        #expect(clipboard.lastWritten == "Translated")
    }

    @Test("Copy Original Text writes full bubble text")
    func copyOriginalTextWritesFullBubbleText() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(text: "Full original OCR text without truncation", translated: "Translated")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyOriginalText()

        #expect(clipboard.lastWritten == "Full original OCR text without truncation")
    }

    @Test("Copy Both writes correct format")
    func copyBothWritesFormattedString() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(text: "原文", translated: "Translated")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyBoth()

        #expect(clipboard.lastWritten == "Original: 原文\nTranslation: Translated")
    }

    @Test("Clipboard returning false does not crash")
    func clipboardFailureDoesNotCrash() {
        let clipboard = FakeClipboard()
        clipboard.shouldSucceed = false
        let bubble = makeBubble()
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyTranslation()

        #expect(clipboard.lastWritten == "Translated text")
    }

    @Test("Empty translatedText writes empty string without error")
    func emptyTranslatedTextWritesEmptyString() {
        let clipboard = FakeClipboard()
        let bubble = makeBubble(translated: "")
        let card = TranslationCard(bubble: bubble, displayNumber: 1, isHighlighted: false, clipboard: clipboard)

        card.copyTranslation()

        #expect(clipboard.lastWritten == "")
    }
}

@Suite("EditCardDecoration.resolve — manual-bubble-editing change")
struct EditCardDecorationTests {

    private func bubble(id: UUID = UUID(), rect: CGRect, text: String = "x") -> TranslatedBubble {
        let cluster = BubbleCluster(
            id: id,
            boundingBox: rect,
            text: text,
            observations: [],
            index: 0
        )
        return TranslatedBubble(bubble: cluster, translatedText: text, index: 0)
    }

    @Test("pendingDelete takes precedence even when geometry equals snapshot")
    func pendingDeleteWins() {
        let id = UUID()
        let snap = bubble(id: id, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let decoration = EditCardDecoration.resolve(
            bubble: snap, snapshot: [snap], deleted: [id]
        )
        #expect(decoration == .pendingDelete)
    }

    @Test("id not in snapshot resolves to .new")
    func newBubble() {
        let snapId = UUID()
        let newId = UUID()
        let snap = bubble(id: snapId, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let new = bubble(id: newId, rect: CGRect(x: 30, y: 30, width: 10, height: 10))
        let decoration = EditCardDecoration.resolve(
            bubble: new, snapshot: [snap], deleted: []
        )
        #expect(decoration == .new)
    }

    @Test("geometry changed resolves to .stale")
    func staleBubble() {
        let id = UUID()
        let original = bubble(id: id, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let moved = bubble(id: id, rect: CGRect(x: 5, y: 0, width: 10, height: 10))
        let decoration = EditCardDecoration.resolve(
            bubble: moved, snapshot: [original], deleted: []
        )
        #expect(decoration == .stale)
    }

    @Test("identical geometry resolves to .unchanged")
    func unchangedBubble() {
        let id = UUID()
        let snap = bubble(id: id, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let decoration = EditCardDecoration.resolve(
            bubble: snap, snapshot: [snap], deleted: []
        )
        #expect(decoration == .unchanged)
    }
}

@Suite("Group-delete with partial un-stage — design.md §D2 worked example")
@MainActor
struct GroupDeletePartialUnstageTests {

    // Reproduces the worked example verbatim: the user deletes
    // {a, b, c, d, e} as one .multi, un-stages c, then walks Cmd+Z twice +
    // Cmd+Shift+Z. The deletedBubbleIds set must converge to
    // {a, b, d, e} → {a, b, c, d, e} → {} → {a, b, c, d, e} without any
    // duplication or loss.
    @Test("delete-then-unstage-then-Cmd+Z-Cmd+Z-Cmd+Shift+Z converges deterministically")
    func partialUnstageRoundTrip() {
        // Use TranslationViewModel directly because EditSession lives there
        // and .multi inverse handling routes through the live view model.
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.sourceLanguage = .ja
        prefs.targetLanguage = .zhHant
        let vm = TranslationViewModel(preferences: prefs)

        let a = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10), text: "a", observations: [], index: 0)
        let b = BubbleCluster(boundingBox: CGRect(x: 20, y: 0, width: 10, height: 10), text: "b", observations: [], index: 1)
        let c = BubbleCluster(boundingBox: CGRect(x: 40, y: 0, width: 10, height: 10), text: "c", observations: [], index: 2)
        let d = BubbleCluster(boundingBox: CGRect(x: 60, y: 0, width: 10, height: 10), text: "d", observations: [], index: 3)
        let e = BubbleCluster(boundingBox: CGRect(x: 80, y: 0, width: 10, height: 10), text: "e", observations: [], index: 4)
        let translated: [TranslatedBubble] = [a, b, c, d, e].map {
            TranslatedBubble(bubble: $0, translatedText: $0.text, index: $0.index)
        }
        var page = MangaPage(imageURL: URL(fileURLWithPath: "/tmp/grpdel.jpg"))
        page.state = .translated(translated)
        vm.pages = [page]
        vm.openEditSession(pageId: vm.pages[0].id)

        // Step 1: delete all 5 as one .multi.
        vm.applyEditAction(.multi([
            .delete(a), .delete(b), .delete(c), .delete(d), .delete(e)
        ]))
        #expect(vm.editSession?.deletedBubbleIds == Set([a.id, b.id, c.id, d.id, e.id]))

        // Step 2: un-stage c.
        vm.applyEditAction(.unstageDelete(c))
        #expect(vm.editSession?.deletedBubbleIds == Set([a.id, b.id, d.id, e.id]))

        // Step 3: Cmd+Z — reverts the unstage; deletedBubbleIds returns to {a,b,c,d,e}.
        vm.undo()
        #expect(vm.editSession?.deletedBubbleIds == Set([a.id, b.id, c.id, d.id, e.id]))

        // Step 4: Cmd+Z — reverts the multi-delete; deletedBubbleIds = {}.
        vm.undo()
        #expect(vm.editSession?.deletedBubbleIds == Set())

        // Step 5: Cmd+Shift+Z — re-applies the multi-delete; back to {a,b,c,d,e}.
        vm.redo()
        #expect(vm.editSession?.deletedBubbleIds == Set([a.id, b.id, c.id, d.id, e.id]))
    }
}
