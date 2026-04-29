import Foundation
import AppKit
import os

#if arch(arm64)
import MLX
import MLXNN

// MARK: - Inference engine protocol (for testability)

public protocol PaddleOCRInferencing: AnyObject {
    func infer(image: CGImage) throws -> (text: String, confidence: Float)
}

// MARK: - Default engine using MLX

public final class DefaultPaddleOCREngine: PaddleOCRInferencing {
    private let modelDirectory: URL
    private let logger = Logger(subsystem: "MangaTranslator", category: "PaddleOCREngine")

    public init(modelDirectory: URL) throws {
        self.modelDirectory = modelDirectory
        guard Self.hasSupportedModelWeights(in: modelDirectory) else {
            throw PaddleOCREngineError.modelUnavailable
        }
    }

    public func infer(image: CGImage) throws -> (text: String, confidence: Float) {
        // TODO: implement full MLX inference pipeline
        logger.warning("PaddleOCR inference not yet implemented — returning empty result")
        return ("", 0)
    }
}

// Minimal error type for the engine layer (avoids importing main target's PaddleOCRError)
public enum PaddleOCREngineError: Error {
    case modelUnavailable
}

private extension DefaultPaddleOCREngine {
    static func hasSupportedModelWeights(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        let candidates = ["weights.npz", "model.safetensors"]
        return candidates.contains { name in
            fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }
}
#endif
