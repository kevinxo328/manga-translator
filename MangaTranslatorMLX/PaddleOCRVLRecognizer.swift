import Foundation
import AppKit
import os

#if arch(arm64)
import MLX
import MLXNN

// MARK: - Inference engine protocol (for testability)

protocol PaddleOCRInferencing: AnyObject {
    func infer(image: CGImage) throws -> (text: String, confidence: Float)
}

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: NSApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryPressure() {
        logger.info("Memory pressure received — unloading PaddleOCR model")
        engine = nil
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
            let fm = FileManager.default
            guard fm.fileExists(atPath: modelDirectory.path) else {
                throw PaddleOCRError.modelUnavailable
            }
            engine = try engineFactory(modelDirectory)
        }

        guard let engine else {
            throw PaddleOCRError.modelUnavailable
        }

        guard let cropped = cgImage.cropping(to: clampedRegion) else {
            return ("", 0)
        }

        return try engine.infer(image: cropped)
    }
}

// MARK: - Default engine using MLX

final class DefaultPaddleOCREngine: PaddleOCRInferencing {
    private let modelDirectory: URL
    private let logger = Logger(subsystem: "MangaTranslator", category: "PaddleOCREngine")

    init(modelDirectory: URL) throws {
        self.modelDirectory = modelDirectory
        // Validate model directory contains expected weights
        let weightsPath = modelDirectory.appendingPathComponent("weights.npz")
        guard FileManager.default.fileExists(atPath: weightsPath.path) else {
            throw PaddleOCRError.modelUnavailable
        }
    }

    func infer(image: CGImage) throws -> (text: String, confidence: Float) {
        // TODO: implement full MLX inference pipeline
        // 1. Preprocess image to model input format
        // 2. Load weights and run forward pass
        // 3. Decode output tokens to text
        // This is a placeholder until the full inference pipeline is implemented
        logger.warning("PaddleOCR inference not yet implemented — returning empty result")
        return ("", 0)
    }
}

#endif
