import XCTest

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
}
