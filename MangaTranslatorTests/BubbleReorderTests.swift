import Testing
import CoreGraphics
@testable import MangaTranslator

@Suite("BubbleReorder")
struct BubbleReorderTests {

    // MARK: - Helpers

    private func makeTranslatedBubble(index: Int, text: String) -> TranslatedBubble {
        var cluster = BubbleCluster(
            boundingBox: CGRect(x: index * 100, y: 0, width: 50, height: 50),
            text: "原文\(index)",
            observations: []
        )
        cluster.index = index
        return TranslatedBubble(bubble: cluster, translatedText: text, index: index)
    }

    // MARK: - 1.2 Adjacent swap with sequential indices

    @Test("move swaps two adjacent items and produces sequential indices")
    func moveSwapsAdjacentItems() {
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "A"),
            makeTranslatedBubble(index: 1, text: "B"),
            makeTranslatedBubble(index: 2, text: "C"),
        ]

        let result = BubbleReorder.move(bubbles: bubbles, from: 0, to: 1)

        #expect(result.map(\.translatedText) == ["B", "A", "C"])
        #expect(result.map(\.index) == [0, 1, 2])
    }

    // MARK: - 1.3 Move from position 0 upward

    @Test("move from position 0 to -1 returns list unchanged")
    func moveUpFromFirstDoesNothing() {
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "A"),
            makeTranslatedBubble(index: 1, text: "B"),
        ]

        let result = BubbleReorder.move(bubbles: bubbles, from: 0, to: -1)

        #expect(result.map(\.translatedText) == ["A", "B"])
        #expect(result.map(\.index) == [0, 1])
    }

    // MARK: - 1.4 Move from last position downward

    @Test("move from last position to count returns list unchanged")
    func moveDownFromLastDoesNothing() {
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "A"),
            makeTranslatedBubble(index: 1, text: "B"),
        ]

        let result = BubbleReorder.move(bubbles: bubbles, from: 1, to: 2)

        #expect(result.map(\.translatedText) == ["A", "B"])
        #expect(result.map(\.index) == [0, 1])
    }

    // MARK: - 1.5 Same position

    @Test("move from same position to same position returns list unchanged")
    func moveSamePositionDoesNothing() {
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "A"),
            makeTranslatedBubble(index: 1, text: "B"),
        ]

        let result = BubbleReorder.move(bubbles: bubbles, from: 1, to: 1)

        #expect(result.map(\.translatedText) == ["A", "B"])
        #expect(result.map(\.index) == [0, 1])
    }

    // MARK: - 1.6 Single element

    @Test("move single-element list returns list unchanged")
    func moveSingleElementDoesNothing() {
        let bubbles = [makeTranslatedBubble(index: 0, text: "A")]

        let result = BubbleReorder.move(bubbles: bubbles, from: 0, to: 0)

        #expect(result.count == 1)
        #expect(result[0].translatedText == "A")
        #expect(result[0].index == 0)
    }

    // MARK: - 1.7 Sequential indices after move

    @Test("after move, all indices are sequential starting from 0")
    func moveProducesSequentialIndices() {
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "A"),
            makeTranslatedBubble(index: 1, text: "B"),
            makeTranslatedBubble(index: 2, text: "C"),
            makeTranslatedBubble(index: 3, text: "D"),
        ]

        let result = BubbleReorder.move(bubbles: bubbles, from: 3, to: 1)

        #expect(result.map(\.index) == [0, 1, 2, 3])
    }

    // MARK: - 1.8 Move from position 2 to position 0

    @Test("move from position 2 to position 0 produces correct order [C, A, B]")
    func moveLastToFirst() {
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "A"),
            makeTranslatedBubble(index: 1, text: "B"),
            makeTranslatedBubble(index: 2, text: "C"),
        ]

        let result = BubbleReorder.move(bubbles: bubbles, from: 2, to: 0)

        #expect(result.map(\.translatedText) == ["C", "A", "B"])
        #expect(result.map(\.index) == [0, 1, 2])
    }

    // MARK: - 3.1 Extract BubbleClusters preserving reordered indices

    @Test("extracting BubbleClusters from reordered TranslatedBubbles preserves order")
    func extractBubbleClustersPreservesReorderedIndices() {
        // Simulate: user reordered bubbles so C is first
        let bubbles = [
            makeTranslatedBubble(index: 0, text: "C"),
            makeTranslatedBubble(index: 1, text: "A"),
            makeTranslatedBubble(index: 2, text: "B"),
        ]

        // This is the extraction logic used by retranslatePage
        let clusters = bubbles.sorted { $0.index < $1.index }.map(\.bubble)

        #expect(clusters.count == 3)
        #expect(clusters.map(\.index) == [0, 1, 2])
        // Original text from the cluster reflects the reordered mapping
        #expect(clusters[0].text == "原文0")
    }
}
