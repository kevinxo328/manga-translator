import Testing
import CoreGraphics
import Foundation
@testable import MangaTranslator

@Suite("EditAction.applyInverse — undo semantics")
struct EditActionTests {

    // MARK: - Helpers

    private func bubble(
        id: UUID = UUID(),
        x: CGFloat = 0,
        y: CGFloat = 0,
        w: CGFloat = 50,
        h: CGFloat = 50,
        text: String = "",
        index: Int = 0,
        isManual: Bool = false
    ) -> BubbleCluster {
        BubbleCluster(
            id: id,
            boundingBox: CGRect(x: x, y: y, width: w, height: h),
            text: text,
            observations: [],
            index: index,
            isInverted: false,
            isManual: isManual
        )
    }

    private func session(with bubbles: [BubbleCluster]) -> EditSession {
        EditSession(
            pageId: UUID(),
            workingBubbles: bubbles,
            originalSnapshot: bubbles.map {
                TranslatedBubble(bubble: $0, translatedText: "", index: $0.index)
            },
            originalPageState: .translated([])
        )
    }

    // MARK: - .add

    @Test(".add inverse removes the bubble and redensifies indices")
    func addInverse() {
        let existingA = bubble(text: "A", index: 0)
        let existingB = bubble(text: "B", index: 1)
        let added = bubble(text: "+", index: 1, isManual: true)
        // Apply state after a hypothetical `.add` at position 1.
        var s = session(with: [existingA, added, existingB])
        // Re-densify so positions match indices (`.add`'s apply path
        // redensifies post-insert; the test mirrors that post-state).
        EditAction.redensifyIndices(&s.workingBubbles)
        #expect(s.workingBubbles.map(\.index) == [0, 1, 2])

        EditAction.add(added).applyInverse(to: &s)

        #expect(s.workingBubbles.count == 2)
        #expect(s.workingBubbles.contains { $0.id == existingA.id })
        #expect(s.workingBubbles.contains { $0.id == existingB.id })
        #expect(!s.workingBubbles.contains { $0.id == added.id })
        // Indices redensified after removal.
        #expect(s.workingBubbles.map(\.index) == [0, 1])
    }

    // MARK: - .delete / .unstageDelete idempotence

    @Test(".delete inverse removes id from deletedBubbleIds; second apply is a no-op")
    func deleteInverseIdempotent() {
        let b = bubble(text: "X")
        var s = session(with: [b])
        s.deletedBubbleIds = [b.id]

        EditAction.delete(b).applyInverse(to: &s)
        #expect(s.deletedBubbleIds.isEmpty)

        // Second apply is idempotent — set still empty.
        EditAction.delete(b).applyInverse(to: &s)
        #expect(s.deletedBubbleIds.isEmpty)

        // workingBubbles untouched by the inverse — the staged delete never
        // removed the bubble from working state to begin with.
        #expect(s.workingBubbles.count == 1)
        #expect(s.workingBubbles[0].id == b.id)
    }

    @Test(".unstageDelete inverse re-inserts id; second apply is a no-op")
    func unstageDeleteInverseIdempotent() {
        let b = bubble(text: "Y")
        var s = session(with: [b])
        s.deletedBubbleIds = []

        EditAction.unstageDelete(b).applyInverse(to: &s)
        #expect(s.deletedBubbleIds == [b.id])

        EditAction.unstageDelete(b).applyInverse(to: &s)
        #expect(s.deletedBubbleIds == [b.id])
    }

    // MARK: - .move / .resize — boundingBox restored, isManual sticky

    @Test(".move inverse restores boundingBox but leaves isManual = true")
    func moveInverseStickyIsManual() {
        let id = UUID()
        let original = CGRect(x: 0, y: 0, width: 50, height: 50)
        let moved = CGRect(x: 30, y: 40, width: 50, height: 50)
        // Post-apply: the bubble already has the moved rect and isManual = true.
        let movedBubble = BubbleCluster(
            id: id,
            boundingBox: moved,
            text: "M",
            observations: [],
            index: 0,
            isInverted: false,
            isManual: true
        )
        var s = session(with: [movedBubble])

        EditAction.move(id: id, from: original, to: moved).applyInverse(to: &s)

        #expect(s.workingBubbles[0].boundingBox == original)
        #expect(s.workingBubbles[0].isManual == true) // sticky — NOT reset
    }

    @Test(".resize inverse restores boundingBox but leaves isManual = true")
    func resizeInverseStickyIsManual() {
        let id = UUID()
        let original = CGRect(x: 0, y: 0, width: 50, height: 50)
        let resized = CGRect(x: 0, y: 0, width: 120, height: 80)
        let resizedBubble = BubbleCluster(
            id: id,
            boundingBox: resized,
            text: "R",
            observations: [],
            index: 0,
            isInverted: false,
            isManual: true
        )
        var s = session(with: [resizedBubble])

        EditAction.resize(id: id, from: original, to: resized).applyInverse(to: &s)

        #expect(s.workingBubbles[0].boundingBox == original)
        #expect(s.workingBubbles[0].isManual == true)
    }

    // MARK: - .reorder

    @Test(".reorder inverse restores the prior ordering and redensifies indices")
    func reorderInverseRestoresOrder() {
        let a = bubble(text: "A", index: 0)
        let b = bubble(text: "B", index: 1)
        let c = bubble(text: "C", index: 2)
        let priorOrder = [a.id, b.id, c.id]
        let newOrder = [c.id, a.id, b.id]
        // Post-apply state: bubbles reordered to newOrder with redensified indices.
        var reordered = EditAction.reorder([a, b, c], byIds: newOrder)
        EditAction.redensifyIndices(&reordered)
        var s = session(with: reordered)

        EditAction.reorder(from: priorOrder, to: newOrder).applyInverse(to: &s)

        #expect(s.workingBubbles.map(\.id) == priorOrder)
        #expect(s.workingBubbles.map(\.index) == [0, 1, 2])
    }

    // MARK: - .multi — reverse order

    @Test(".multi inverse applies its sub-inverses in reverse order")
    func multiInverseReverseOrder() {
        // Construct a sequence where order matters: move A from r0→r1, then
        // resize A from r1→r2. Inverse should restore r1 first (undo resize),
        // then r0 (undo move). Applying in forward order would jump straight
        // from r2 to r0 without ever visiting r1 — observably different only
        // if a sub-action depends on the intermediate state. Use an inverse
        // sequence whose final boundingBox value differs based on order.
        let id = UUID()
        let r0 = CGRect(x: 0, y: 0, width: 50, height: 50)
        let r1 = CGRect(x: 10, y: 0, width: 50, height: 50)
        let r2 = CGRect(x: 10, y: 0, width: 100, height: 50)

        let finalBubble = BubbleCluster(
            id: id,
            boundingBox: r2,
            text: "X",
            observations: [],
            index: 0,
            isInverted: false,
            isManual: true
        )
        var s = session(with: [finalBubble])

        let multi = EditAction.multi([
            .move(id: id, from: r0, to: r1),
            .resize(id: id, from: r1, to: r2)
        ])
        multi.applyInverse(to: &s)

        // Reverse order: resize inverse first (r2 → r1), then move inverse
        // (r1 → r0). Final value should be r0.
        #expect(s.workingBubbles[0].boundingBox == r0)
    }

    @Test(".multi inverse applied in forward order would yield wrong result")
    func multiInverseOrderRegressionGuard() {
        // Sanity guard: simulate the WRONG implementation (forward order)
        // and confirm it produces a different boundingBox than the
        // implementation. This rejects any future refactor that drops the
        // .reversed() call.
        let id = UUID()
        let r0 = CGRect(x: 0, y: 0, width: 50, height: 50)
        let r1 = CGRect(x: 10, y: 0, width: 50, height: 50)
        let r2 = CGRect(x: 10, y: 0, width: 100, height: 50)

        let final = BubbleCluster(
            id: id,
            boundingBox: r2,
            text: "X",
            observations: [],
            index: 0,
            isInverted: false,
            isManual: true
        )
        var sForward = session(with: [final])
        // Forward-order application of sub-inverses.
        let actions: [EditAction] = [
            .move(id: id, from: r0, to: r1),
            .resize(id: id, from: r1, to: r2)
        ]
        for a in actions {
            a.applyInverse(to: &sForward)
        }
        // Forward order: move inverse first (r2 → r0), then resize inverse
        // (r0 → r1). Final value is r1, NOT r0.
        #expect(sForward.workingBubbles[0].boundingBox == r1)

        // Now via the .multi inverse — reverse order — expect r0 instead.
        var sMulti = session(with: [final])
        EditAction.multi(actions).applyInverse(to: &sMulti)
        #expect(sMulti.workingBubbles[0].boundingBox == r0)
        #expect(sMulti.workingBubbles[0].boundingBox != sForward.workingBubbles[0].boundingBox)
    }

    // MARK: - .move inverse on auto bubble — isManual stays true after undo

    @Test("Undoing the move that flipped isManual leaves the flag sticky at true")
    func autoBubbleMovedThenUndone() {
        let id = UUID()
        let pre = CGRect(x: 0, y: 0, width: 50, height: 50)
        let post = CGRect(x: 5, y: 0, width: 50, height: 50)
        // Post-apply state: bubble moved and isManual flipped from false → true.
        let bubbleAfterMove = BubbleCluster(
            id: id,
            boundingBox: post,
            text: "auto",
            observations: [],
            index: 0,
            isInverted: false,
            isManual: true
        )
        var s = session(with: [bubbleAfterMove])

        EditAction.move(id: id, from: pre, to: post).applyInverse(to: &s)

        #expect(s.workingBubbles[0].boundingBox == pre)
        #expect(s.workingBubbles[0].isManual == true)
    }
}
