import Testing
import CoreGraphics
@testable import MangaTranslator

@Suite("ComicTextDetector")
struct ComicTextDetectorTests {

    // Task 2.1: confidence 0.50 rejected, 0.78 kept by new threshold (0.60)
    @Test("postprocessYolo rejects predictions at conf 0.50 and keeps 0.78")
    func confidenceFiltering() {
        // Build synthetic predictions for a single box at conf 0.50
        // Format: [cx, cy, w, h, objectness, class0, class1]
        // conf = objectness * max(class0, class1)
        // For conf=0.50: objectness=1.0, class0=0.0, class1=0.50
        // For conf=0.78: objectness=1.0, class0=0.0, class1=0.78
        var preds050 = [Float](repeating: 0, count: 7)
        preds050[0] = 512; preds050[1] = 512  // cx, cy
        preds050[2] = 100; preds050[3] = 100  // w, h
        preds050[4] = 1.0                      // objectness
        preds050[5] = 0.0                      // class0
        preds050[6] = 0.50                     // class1 → conf=0.50

        var preds078 = [Float](repeating: 0, count: 7)
        preds078[0] = 512; preds078[1] = 512
        preds078[2] = 100; preds078[3] = 100
        preds078[4] = 1.0
        preds078[5] = 0.0
        preds078[6] = 0.78  // conf=0.78

        let service = ComicTextDetectorService()

        let (result050, _) = service.testPostprocessYolo(predictions: preds050, numBoxes: 1, numOutputs: 7, origW: 1024, origH: 1024, resizedW: 1024, resizedH: 1024)
        #expect(result050.isEmpty, "conf=0.50 should be rejected by threshold 0.60")

        let (result078, _) = service.testPostprocessYolo(predictions: preds078, numBoxes: 1, numOutputs: 7, origW: 1024, origH: 1024, resizedW: 1024, resizedH: 1024)
        #expect(result078.count == 1, "conf=0.78 should be kept by threshold 0.60")
    }

    // Task 2.5: empty detection page yields nil textPixelMask
    @Test("Empty-detection page yields nil textPixelMask in result")
    func emptyDetectionYieldsNilMask() {
        let emptyResult = ComicTextDetectorResult(regions: [], textPixelMask: nil, lowConfidenceRegionCount: 0)
        #expect(emptyResult.textPixelMask == nil)
        #expect(emptyResult.regions.isEmpty)
    }

    // Task 2.6: lowConfidenceRegionCount counts [0.40, 0.60) band
    @Test("Low confidence band counting is correct")
    func lowConfidenceBandCounting() {
        // Two predictions: 0.45 and 0.52 (in band [0.40, 0.60)), one at 0.95 (above band)
        var preds = [Float](repeating: 0, count: 21)  // 3 boxes × 7 outputs
        // box 0: conf=0.45 (in band)
        preds[0]=512; preds[1]=512; preds[2]=100; preds[3]=100; preds[4]=1.0; preds[5]=0.0; preds[6]=0.45
        // box 1: conf=0.52 (in band)
        preds[7]=200; preds[8]=200; preds[9]=50; preds[10]=50; preds[11]=1.0; preds[12]=0.0; preds[13]=0.52
        // box 2: conf=0.95 (above band, also above threshold → kept)
        preds[14]=700; preds[15]=700; preds[16]=80; preds[17]=80; preds[18]=1.0; preds[19]=0.0; preds[20]=0.95

        let service = ComicTextDetectorService()
        let (_, lowCount) = service.testPostprocessYolo(predictions: preds, numBoxes: 3, numOutputs: 7, origW: 1024, origH: 1024, resizedW: 1024, resizedH: 1024)
        #expect(lowCount == 2, "Expected 2 predictions in [0.40, 0.60) band")
    }

    @Test("Low confidence count tracks raw predictions even when NMS merges boxes")
    func lowConfidenceCountUsesRawPredictions() {
        var preds = [Float](repeating: 0, count: 14)
        // Two overlapping boxes in the low-confidence band should count as 2 raw detections.
        preds[0] = 512; preds[1] = 512; preds[2] = 100; preds[3] = 100; preds[4] = 1.0; preds[5] = 0.0; preds[6] = 0.45
        preds[7] = 514; preds[8] = 514; preds[9] = 100; preds[10] = 100; preds[11] = 1.0; preds[12] = 0.0; preds[13] = 0.52

        let service = ComicTextDetectorService()
        let (_, lowCount) = service.testPostprocessYolo(predictions: preds, numBoxes: 2, numOutputs: 7, origW: 1024, origH: 1024, resizedW: 1024, resizedH: 1024)
        #expect(lowCount == 2, "Raw low-confidence predictions should be counted before NMS")
    }
}
