import Foundation
import AppKit

protocol OCRRecognizing: AnyObject, Sendable {
    func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float)
    func unload()
}

extension OCRRecognizing {
    func unload() {} // Default empty implementation for recognizers that don't need it
}
