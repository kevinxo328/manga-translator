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
        manga: [BubbleCluster],
        vision: [BubbleCluster],
        threshold: Float = 0.5
    ) -> (paired: [PairedRegionResult], unmatchedManga: [BubbleCluster], unmatchedVision: [BubbleCluster]) {
        var paired: [PairedRegionResult] = []
        var remainingManga = manga
        var remainingVision = vision
        
        // Find all possible pairings above threshold
        struct CandidatePair {
            let mangaIndex: Int
            let visionIndex: Int
            let iou: Float
        }
        
        var candidates: [CandidatePair] = []
        for i in 0..<remainingManga.count {
            for j in 0..<remainingVision.count {
                let score = IoUCalculator.iou(remainingManga[i].boundingBox, remainingVision[j].boundingBox)
                if score >= threshold {
                    candidates.append(CandidatePair(mangaIndex: i, visionIndex: j, iou: score))
                }
            }
        }
        
        // Sort by IoU descending for greedy matching
        candidates.sort { $0.iou > $1.iou }
        
        var matchedMangaIndices = Set<Int>()
        var matchedVisionIndices = Set<Int>()
        
        for candidate in candidates {
            if !matchedMangaIndices.contains(candidate.mangaIndex) && 
               !matchedVisionIndices.contains(candidate.visionIndex) {
                paired.append(PairedRegionResult(
                    mangaBubble: remainingManga[candidate.mangaIndex],
                    visionBubble: remainingVision[candidate.visionIndex],
                    iou: candidate.iou
                ))
                matchedMangaIndices.insert(candidate.mangaIndex)
                matchedVisionIndices.insert(candidate.visionIndex)
            }
        }
        
        let unmatchedManga = remainingManga.enumerated()
            .filter { !matchedMangaIndices.contains($0.offset) }
            .map { $0.element }
            
        let unmatchedVision = remainingVision.enumerated()
            .filter { !matchedVisionIndices.contains($0.offset) }
            .map { $0.element }
            
        return (paired, unmatchedManga, unmatchedVision)
    }
}
