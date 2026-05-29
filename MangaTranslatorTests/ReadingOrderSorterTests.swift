import Testing
import CoreGraphics
import Foundation
@testable import MangaTranslator

@Suite("ReadingOrderSorter.insertNearestNeighbour")
struct ReadingOrderSorterTests {

    private func bubble(
        cx: CGFloat,
        cy: CGFloat,
        w: CGFloat = 40,
        h: CGFloat = 40,
        index: Int = 0
    ) -> BubbleCluster {
        BubbleCluster(
            boundingBox: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h),
            text: "",
            observations: [],
            index: index
        )
    }

    @Test("Insert into empty order returns single element with index 0")
    func insertIntoEmpty() {
        let n = bubble(cx: 100, cy: 100)
        let result = ReadingOrderSorter.insertNearestNeighbour(n, into: [])

        #expect(result.count == 1)
        #expect(result[0].id == n.id)
        #expect(result[0].index == 0)
    }

    @Test("Insert lands immediately after the geometrically nearest neighbour")
    func insertAfterNearest() {
        // Three pre-existing bubbles at known centres; the new bubble's centre
        // is closest to the first entry. Expected post-state: new bubble at
        // array position 1 (right after the nearest), all indices `0..<4`.
        let a = bubble(cx: 100, cy: 100, index: 0) // nearest
        let b = bubble(cx: 500, cy: 100, index: 1)
        let c = bubble(cx: 100, cy: 500, index: 2)
        let n = bubble(cx: 120, cy: 110)

        let result = ReadingOrderSorter.insertNearestNeighbour(n, into: [a, b, c])

        #expect(result.count == 4)
        #expect(result.map(\.id) == [a.id, n.id, b.id, c.id])
        #expect(result.map(\.index) == [0, 1, 2, 3])
    }

    @Test("Tie broken by smaller (midY, midX) of the candidate's centre")
    func tieBreakerLowerYThenX() {
        // Two candidates equidistant from the new bubble. Candidate B has
        // smaller midY than candidate A, so B SHALL be selected.
        let a = bubble(cx: 100, cy: 200, w: 0, h: 0, index: 0) // A: (100, 200)
        let bCand = bubble(cx: 200, cy: 100, w: 0, h: 0, index: 1) // B: (200, 100)
        // New centre placed equidistant from A and B (distance √(100² + 100²) each)
        // The new centre at (200, 200) is at distance 100 from A and 100 from B.
        let n = bubble(cx: 200, cy: 200, w: 0, h: 0)

        let result = ReadingOrderSorter.insertNearestNeighbour(n, into: [a, bCand])

        // B should be picked (lower midY), so new bubble inserts AFTER B.
        #expect(result.map(\.id) == [a.id, bCand.id, n.id])
        #expect(result.map(\.index) == [0, 1, 2])
    }

    @Test("Pre-existing relative order is preserved after insertion")
    func preExistingOrderPreserved() {
        // Simulate a user's manual reorder that differs from geometric order:
        // bubbles laid out diagonally but reordered to a non-monotone sequence.
        // The new bubble's nearest neighbour is at array index 2; everything
        // else SHALL keep its relative order with only its index shifted.
        let a = bubble(cx: 50, cy: 50, index: 0)
        let b = bubble(cx: 400, cy: 400, index: 1)
        let c = bubble(cx: 200, cy: 200, index: 2) // nearest to new (210, 210)
        let d = bubble(cx: 600, cy: 600, index: 3)
        let n = bubble(cx: 210, cy: 210)

        let result = ReadingOrderSorter.insertNearestNeighbour(n, into: [a, b, c, d])

        #expect(result.map(\.id) == [a.id, b.id, c.id, n.id, d.id])
        #expect(result.map(\.index) == [0, 1, 2, 3, 4])
        // Every pre-existing pairwise relative order is preserved.
        let originalOrder = [a.id, b.id, c.id, d.id]
        let preservedIds = result.map(\.id).filter { $0 != n.id }
        #expect(preservedIds == originalOrder)
    }
}
