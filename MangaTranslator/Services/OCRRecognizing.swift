import Foundation
import AppKit

@MainActor
protocol OCRRecognizing: AnyObject {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float)
    func unload()
}

@MainActor
extension OCRRecognizing {
    func unload() {} // Default empty implementation for recognizers that don't need it
}
