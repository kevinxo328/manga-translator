import Foundation
import AppKit

protocol OCRRecognizing: AnyObject {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float)
}
