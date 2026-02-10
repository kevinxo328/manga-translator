import Foundation
import CoreGraphics

struct ReadingOrderSorter {
    func sort(_ bubbles: [BubbleCluster]) -> [BubbleCluster] {
        guard bubbles.count > 1 else { return bubbles }

        let rows = partitionIntoRows(bubbles)
        let sortedRows = rows.sorted { $0.first!.boundingBox.origin.y < $1.first!.boundingBox.origin.y }

        var result: [BubbleCluster] = []
        for row in sortedRows {
            let sortedRow = row.sorted { $0.boundingBox.origin.x > $1.boundingBox.origin.x }
            result.append(contentsOf: sortedRow)
        }

        return result.enumerated().map { index, bubble in
            var b = bubble
            b.index = index
            return b
        }
    }

    private func partitionIntoRows(_ bubbles: [BubbleCluster]) -> [[BubbleCluster]] {
        let sorted = bubbles.sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }
        var rows: [[BubbleCluster]] = []

        for bubble in sorted {
            var placed = false
            for i in rows.indices {
                if overlapsVertically(bubble, with: rows[i]) {
                    rows[i].append(bubble)
                    placed = true
                    break
                }
            }
            if !placed {
                rows.append([bubble])
            }
        }

        return rows
    }

    private func overlapsVertically(_ bubble: BubbleCluster, with row: [BubbleCluster]) -> Bool {
        let bubbleMinY = bubble.boundingBox.origin.y
        let bubbleMaxY = bubbleMinY + bubble.boundingBox.height

        for existing in row {
            let existingMinY = existing.boundingBox.origin.y
            let existingMaxY = existingMinY + existing.boundingBox.height

            let overlapStart = max(bubbleMinY, existingMinY)
            let overlapEnd = min(bubbleMaxY, existingMaxY)
            let overlap = overlapEnd - overlapStart

            let minHeight = min(bubble.boundingBox.height, existing.boundingBox.height)
            if minHeight > 0 && overlap / minHeight > 0.3 {
                return true
            }
        }

        return false
    }
}
