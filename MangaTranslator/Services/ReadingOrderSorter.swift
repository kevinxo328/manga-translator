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

    // MARK: - Edit Mode insertion

    // Places `newBox` into an already-ordered array without re-sorting any
    // existing entry. Used by Edit Mode's `.add` action so newly drawn bubbles
    // land at their geometric position rather than at the end of the list —
    // and so any prior manual ordering (sidebar drag-to-reorder) is preserved.
    //
    // Algorithm (see `openspec/changes/manual-bubble-editing/specs/reading-order/spec.md`
    // and `design.md` §D4):
    //   1. Empty input → return `[newBox]` with `index = 0`.
    //   2. Otherwise pick the existing entry whose centre is the Euclidean
    //      nearest to `newBox`'s centre in image pixel coordinates.
    //   3. Tie-break by smaller `(midY, midX)` of the candidate's centre,
    //      lexicographically ascending.
    //   4. Insert `newBox` immediately *after* the nearest neighbour.
    //   5. Redensify every entry's `index` to its new array position
    //      (`0..<n`) and return.
    //
    // The function is pure and deterministic; it never re-sorts existing
    // entries or consults global state.
    static func insertNearestNeighbour(_ newBox: BubbleCluster, into ordered: [BubbleCluster]) -> [BubbleCluster] {
        guard !ordered.isEmpty else {
            var only = newBox
            only.index = 0
            return [only]
        }

        let newCentre = CGPoint(x: newBox.boundingBox.midX, y: newBox.boundingBox.midY)
        var bestIndex = 0
        var bestDistanceSquared = CGFloat.greatestFiniteMagnitude
        var bestCentre = CGPoint(
            x: ordered[0].boundingBox.midX,
            y: ordered[0].boundingBox.midY
        )

        for i in ordered.indices {
            let candidate = ordered[i]
            let cx = candidate.boundingBox.midX
            let cy = candidate.boundingBox.midY
            let dx = cx - newCentre.x
            let dy = cy - newCentre.y
            let dSquared = dx * dx + dy * dy
            if dSquared < bestDistanceSquared {
                bestDistanceSquared = dSquared
                bestIndex = i
                bestCentre = CGPoint(x: cx, y: cy)
            } else if dSquared == bestDistanceSquared {
                // Tie-break by ascending (midY, midX) of the candidate's centre.
                if cy < bestCentre.y || (cy == bestCentre.y && cx < bestCentre.x) {
                    bestIndex = i
                    bestCentre = CGPoint(x: cx, y: cy)
                }
            }
        }

        var result = ordered
        result.insert(newBox, at: bestIndex + 1)
        for i in result.indices {
            result[i].index = i
        }
        return result
    }
}
