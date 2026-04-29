import Foundation
import AppKit
import CoreImage
import os

#if arch(arm64)
import MLX
import MLXNN
import PaddleOCRVL

// MARK: - Inference engine protocol (for testability)

public protocol PaddleOCRInferencing: AnyObject {
    func infer(image: CGImage) throws -> (text: String, confidence: Float)
}

// MARK: - Default engine using MLX

public final class DefaultPaddleOCREngine: PaddleOCRInferencing {
    private let modelDirectory: URL
    private var pipeline: PaddleOCRVLPipeline?
    private let pipelineLock = NSLock()
    private let logger = Logger(subsystem: "MangaTranslator", category: "PaddleOCREngine")

    public init(modelDirectory: URL) throws {
        self.modelDirectory = modelDirectory
        guard Self.hasRequiredArtifacts(in: modelDirectory) else {
            throw PaddleOCREngineError.modelUnavailable
        }
    }

    public func infer(image: CGImage) throws -> (text: String, confidence: Float) {
        guard image.width > 0 && image.height > 0 else {
            throw PaddleOCREngineError.invalidInputImage
        }
        let runtime = try loadPipelineIfNeeded()
        let ciImage = CIImage(cgImage: image)
        let text = runtime.recognize(image: ciImage, task: .ocr, maxTokens: 1024).trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence: Float = text.isEmpty ? 0 : 1
        return (text, confidence)
    }

    private func loadPipelineIfNeeded() throws -> PaddleOCRVLPipeline {
        pipelineLock.lock()
        defer { pipelineLock.unlock() }

        if let pipeline {
            return pipeline
        }
        do {
            let created = try Self.runBlocking {
                try await PaddleOCRVLPipeline(modelURL: self.modelDirectory, mode: .base)
            }
            pipeline = created
            return created
        } catch {
            logger.error("Failed to initialize PaddleOCR pipeline: \(error.localizedDescription)")
            throw PaddleOCREngineError.runtimeFailure(error.localizedDescription)
        }
    }

    private static func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result!.get()
    }
}

// Minimal error type for the engine layer (avoids importing main target's PaddleOCRError)
public enum PaddleOCREngineError: Error, Equatable {
    case modelUnavailable
    case invalidInputImage
    case runtimeFailure(String)
}

extension PaddleOCREngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "PaddleOCR model artifacts are unavailable."
        case .invalidInputImage:
            return "Input image is invalid."
        case .runtimeFailure(let message):
            return "PaddleOCR runtime failed: \(message)"
        }
    }
}

private extension DefaultPaddleOCREngine {
    static func hasRequiredArtifacts(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            return false
        }
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("generation_config.json").path) else {
            return false
        }
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("tokenizer.json").path) else {
            return false
        }
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("tokenizer_config.json").path) else {
            return false
        }
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("special_tokens_map.json").path) else {
            return false
        }

        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        return files.contains(where: { $0.pathExtension == "safetensors" })
    }
}
#endif
