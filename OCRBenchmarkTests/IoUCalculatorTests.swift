import XCTest
import CoreGraphics
@testable import MangaTranslator

final class IoUCalculatorTests: XCTestCase {

    func testIdenticalBoxes() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(IoUCalculator.iou(box, box), 1.0, accuracy: 0.001)
    }

    func testNoOverlap() {
        let a = CGRect(x: 0, y: 0, width: 50, height: 50)
        let b = CGRect(x: 100, y: 100, width: 50, height: 50)
        XCTAssertEqual(IoUCalculator.iou(a, b), 0.0, accuracy: 0.001)
    }

    func testPartialOverlap() {
        // a: (0,0,100,100), b: (50,0,100,100)
        // intersection: (50,0,50,100) area=5000, union=15000, IoU=1/3
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 50, y: 0, width: 100, height: 100)
        XCTAssertEqual(IoUCalculator.iou(a, b), Float(1.0 / 3.0), accuracy: 0.001)
    }

    // BubbleRegionMatcher Tests
    
    func testFullMatch() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let manga = [BubbleCluster(boundingBox: rect, text: "Manga", observations: [])]
        let vision = [BubbleCluster(boundingBox: rect, text: "Vision", observations: [])]
        
        let result = BubbleRegionMatcher.match(manga: manga, vision: vision)
        
        XCTAssertEqual(result.paired.count, 1)
        XCTAssertEqual(result.paired[0].iou, 1.0)
        XCTAssertEqual(result.unmatchedManga.count, 0)
        XCTAssertEqual(result.unmatchedVision.count, 0)
    }

    func testPartialMatch() {
        let rectA = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rectB = CGRect(x: 50, y: 0, width: 100, height: 100) // IoU = 1/3
        let manga = [BubbleCluster(boundingBox: rectA, text: "Manga", observations: [])]
        let vision = [BubbleCluster(boundingBox: rectB, text: "Vision", observations: [])]
        
        // With default 0.5 threshold, they shouldn't match
        let result = BubbleRegionMatcher.match(manga: manga, vision: vision)
        XCTAssertEqual(result.paired.count, 0)
        XCTAssertEqual(result.unmatchedManga.count, 1)
        XCTAssertEqual(result.unmatchedVision.count, 1)
        
        // With 0.3 threshold, they should match
        let resultLow = BubbleRegionMatcher.match(manga: manga, vision: vision, threshold: 0.3)
        XCTAssertEqual(resultLow.paired.count, 1)
        XCTAssertEqual(resultLow.paired[0].iou, Float(1.0/3.0), accuracy: 0.001)
    }

    func testNoMatch() {
        let rectA = CGRect(x: 0, y: 0, width: 50, height: 50)
        let rectB = CGRect(x: 100, y: 100, width: 50, height: 50)
        let manga = [BubbleCluster(boundingBox: rectA, text: "Manga", observations: [])]
        let vision = [BubbleCluster(boundingBox: rectB, text: "Vision", observations: [])]
        
        let result = BubbleRegionMatcher.match(manga: manga, vision: vision)
        XCTAssertEqual(result.paired.count, 0)
        XCTAssertEqual(result.unmatchedManga.count, 1)
        XCTAssertEqual(result.unmatchedVision.count, 1)
    }

    func testEmptyInputs() {
        let result = BubbleRegionMatcher.match(manga: [], vision: [])
        XCTAssertEqual(result.paired.count, 0)
        XCTAssertEqual(result.unmatchedManga.count, 0)
        XCTAssertEqual(result.unmatchedVision.count, 0)
    }

    func testGreedyMatching() {
        let mangaA = BubbleCluster(boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100), text: "A", observations: [])
        let mangaB = BubbleCluster(boundingBox: CGRect(x: 200, y: 200, width: 100, height: 100), text: "B", observations: [])
        
        let vision1 = BubbleCluster(boundingBox: CGRect(x: 10, y: 0, width: 100, height: 100), text: "1", observations: []) // IoU with A = 90/110 ~ 0.818
        let vision2 = BubbleCluster(boundingBox: CGRect(x: 205, y: 200, width: 100, height: 100), text: "2", observations: []) // IoU with B = 95/105 ~ 0.904
        
        let result = BubbleRegionMatcher.match(manga: [mangaA, mangaB], vision: [vision1, vision2])
        
        XCTAssertEqual(result.paired.count, 2)
        XCTAssertTrue(result.paired.contains { $0.mangaBubble?.text == "B" && $0.visionBubble?.text == "2" })
        XCTAssertTrue(result.paired.contains { $0.mangaBubble?.text == "A" && $0.visionBubble?.text == "1" })
    }
}
