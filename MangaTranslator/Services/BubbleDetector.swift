import Foundation
import CoreGraphics

struct BubbleDetector {
    func detectBubbles(from observations: [TextObservation]) -> [BubbleCluster] {
        guard !observations.isEmpty else { return [] }

        let threshold = adaptiveThreshold(for: observations)
        var clusters = observations.map { [$0] }

        var merged = true
        while merged {
            merged = false
            var i = 0
            while i < clusters.count {
                var j = i + 1
                while j < clusters.count {
                    if shouldMerge(clusters[i], clusters[j], threshold: threshold) {
                        clusters[i].append(contentsOf: clusters[j])
                        clusters.remove(at: j)
                        merged = true
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }

        return clusters.enumerated().map { index, observations in
            let boundingBox = unionRect(of: observations)
            let sortedByY = observations.sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }
            let text = sortedByY.map(\.text).joined(separator: " ")
            return BubbleCluster(
                boundingBox: boundingBox,
                text: text,
                observations: observations,
                index: index
            )
        }
    }

    private func adaptiveThreshold(for observations: [TextObservation]) -> CGFloat {
        let heights = observations.map(\.boundingBox.height).sorted()
        guard !heights.isEmpty else { return 20 }
        let median = heights[heights.count / 2]
        return median * 2.0
    }

    private func shouldMerge(
        _ clusterA: [TextObservation],
        _ clusterB: [TextObservation],
        threshold: CGFloat
    ) -> Bool {
        let rectA = unionRect(of: clusterA)
        let rectB = unionRect(of: clusterB)
        let distance = minEdgeDistance(rectA, rectB)
        return distance < threshold
    }

    private func unionRect(of observations: [TextObservation]) -> CGRect {
        guard let first = observations.first else { return .zero }
        return observations.dropFirst().reduce(first.boundingBox) { result, obs in
            result.union(obs.boundingBox)
        }
    }

    private func minEdgeDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx: CGFloat
        if a.maxX < b.minX {
            dx = b.minX - a.maxX
        } else if b.maxX < a.minX {
            dx = a.minX - b.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if a.maxY < b.minY {
            dy = b.minY - a.maxY
        } else if b.maxY < a.minY {
            dy = a.minY - b.maxY
        } else {
            dy = 0
        }

        return sqrt(dx * dx + dy * dy)
    }
}
