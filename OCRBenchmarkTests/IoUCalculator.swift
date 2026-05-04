import CoreGraphics

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
