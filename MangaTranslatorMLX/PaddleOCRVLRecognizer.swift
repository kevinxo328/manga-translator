import Foundation
import CoreGraphics
import os

#if arch(arm64)
import MangaTranslatorMLX

// MARK: - PaddleOCRVLRecognizer

@MainActor
public final class PaddleOCRVLRecognizer: OCRRecognizing {
    private var engine: (any PaddleOCRInferencing)?
    private let modelDirectory: URL
    private let engineFactory: (URL) throws -> any PaddleOCRInferencing
    private let logger = Logger(subsystem: "MangaTranslator", category: "PaddleOCRVL")

    convenience public init(modelDirectory: URL) {
        self.init(modelDirectory: modelDirectory) { dir in
            try DefaultPaddleOCREngine(modelDirectory: dir)
        }
    }

    init(modelDirectory: URL, engineFactory: @escaping (URL) throws -> any PaddleOCRInferencing) {
        self.modelDirectory = modelDirectory
        self.engineFactory = engineFactory
    }

    public func unload() {
        engine = nil
    }

    // MARK: - OCRRecognizing

    public func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clampedRegion = region.intersection(imageBounds)

        guard clampedRegion.width > 0 && clampedRegion.height > 0 else {
            return ("", 0)
        }

        if engine == nil {
            guard let resolvedModelDirectory = ModelDownloadService.resolvedModelDirectory(in: modelDirectory) else {
                throw PaddleOCRError.modelUnavailable
            }
            do {
                engine = try engineFactory(resolvedModelDirectory)
            } catch {
                throw PaddleOCRError.modelUnavailable
            }
        }

        guard let engine else {
            throw PaddleOCRError.modelUnavailable
        }

        guard let cropped = cgImage.cropping(to: clampedRegion) else {
            return ("", 0)
        }

        do {
            return try engine.infer(image: cropped)
        } catch {
            throw Self.mapEngineError(error)
        }
    }

    private static func mapEngineError(_ error: Error) -> PaddleOCRError {
        if let paddleError = error as? PaddleOCRError {
            return paddleError
        }
        if let engineError = error as? PaddleOCREngineError {
            switch engineError {
            case .modelUnavailable:
                return .modelUnavailable
            case .invalidInputImage:
                return .inferenceFailed("Invalid input image")
            case .runtimeFailure(let message):
                if isIncompatibleQuantizedWeights(message) {
                    return .verifyFailed
                }
                return .inferenceFailed(message)
            }
        }
        return .inferenceFailed(error.localizedDescription)
    }

    private static func isIncompatibleQuantizedWeights(_ message: String) -> Bool {
        message.contains("Unhandled keys")
            && message.contains("\"biases\"")
            && message.contains("\"scales\"")
    }
}
#endif
