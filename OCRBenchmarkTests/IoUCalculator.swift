import CoreGraphics
@testable import MangaTranslator

enum IoUCalculator {
    static func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0.0 }
        let intersectionArea = Float(intersection.width * intersection.height)
        let unionArea = Float(a.width * a.height) + Float(b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0.0 }
        return intersectionArea / unionArea
    }
}

struct BubbleRegionMatcher {
    static func match(
        anchor: [BubbleCluster],
        compared: [BubbleCluster],
        threshold: Float = 0.5
    ) -> (paired: [PairedRegionResult], unmatchedAnchor: [BubbleCluster], unmatchedCompared: [BubbleCluster]) {
        var paired: [PairedRegionResult] = []
        var remainingAnchor = anchor
        var remainingCompared = compared
        
        // Find all possible pairings above threshold
        struct CandidatePair {
            let anchorIndex: Int
            let comparedIndex: Int
            let iou: Float
        }
        
        var candidates: [CandidatePair] = []
        for i in 0..<remainingAnchor.count {
            for j in 0..<remainingCompared.count {
                let score = IoUCalculator.iou(remainingAnchor[i].boundingBox, remainingCompared[j].boundingBox)
                if score >= threshold {
                    candidates.append(CandidatePair(anchorIndex: i, comparedIndex: j, iou: score))
                }
            }
        }
        
        // Sort by IoU descending for greedy matching
        candidates.sort { $0.iou > $1.iou }
        
        var matchedAnchorIndices = Set<Int>()
        var matchedComparedIndices = Set<Int>()
        
        for candidate in candidates {
            if !matchedAnchorIndices.contains(candidate.anchorIndex) && 
               !matchedComparedIndices.contains(candidate.comparedIndex) {
                paired.append(PairedRegionResult(
                    anchorBubble: remainingAnchor[candidate.anchorIndex],
                    comparedBubble: remainingCompared[candidate.comparedIndex],
                    iou: candidate.iou
                ))
                matchedAnchorIndices.insert(candidate.anchorIndex)
                matchedComparedIndices.insert(candidate.comparedIndex)
            }
        }
        
        let unmatchedAnchor = remainingAnchor.enumerated()
            .filter { !matchedAnchorIndices.contains($0.offset) }
            .map { $0.element }
            
        let unmatchedCompared = remainingCompared.enumerated()
            .filter { !matchedComparedIndices.contains($0.offset) }
            .map { $0.element }
            
        return (paired, unmatchedAnchor, unmatchedCompared)
    }
}
