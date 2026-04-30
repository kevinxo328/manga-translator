import Foundation
import AppKit
import CoreImage
import os

#if arch(arm64)
import MLX
import MLXNN
import PaddleOCRVL
import Tokenizers
import Hub

// MARK: - Inference engine protocol (for testability)

public protocol PaddleOCRInferencing: AnyObject {
    func infer(image: CGImage) throws -> (text: String, confidence: Float)
}

// MARK: - Internal runtime container

private struct PaddleOCRVLRuntime {
    let imageProcessor: PaddleOCRVLImageProcessor
    let generator: PaddleOCRVLGenerator

    func recognize(ciImage: CIImage) -> String {
        let processed = imageProcessor.process(ciImage)
        return generator.generate(
            processedImages: processed,
            task: .ocr,
            maxNewTokens: 1024,
            temperature: 0.0,
            topP: 1.0
        ).text
    }
}

// MARK: - Default engine using MLX

public final class DefaultPaddleOCREngine: PaddleOCRInferencing {
    private let modelDirectory: URL
    private var runtime: PaddleOCRVLRuntime?
    private let runtimeLock = NSLock()
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
        let rt = try loadRuntimeIfNeeded()
        let ciImage = CIImage(cgImage: image)
        let text = rt.recognize(ciImage: ciImage).trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence: Float = text.isEmpty ? 0 : 1
        return (text, confidence)
    }

    private func loadRuntimeIfNeeded() throws -> PaddleOCRVLRuntime {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        if let runtime { return runtime }
        do {
            let created = try Self.runBlocking {
                try await Self.buildRuntime(modelDirectory: self.modelDirectory)
            }
            runtime = created
            return created
        } catch {
            logger.error("Failed to initialize PaddleOCR pipeline: \(error.localizedDescription)")
            throw PaddleOCREngineError.runtimeFailure(error.localizedDescription)
        }
    }

    // Bypass PaddleOCRVLPipeline.init() which uses PaddleOCRVLModel.load() — that path
    // lacks MLXNN.quantize() before model.update() and doesn't handle the key-format
    // differences between jzhang533/PaddleOCR-VL-For-Manga (SiglipVisionModel layout,
    // language_model.* prefix, embeddings.patch_embedding sub-module) and the key schema
    // paddleocr-vl.swift was designed for (PaddlePaddle/PaddleOCR-VL).
    private static func buildRuntime(modelDirectory: URL) async throws -> PaddleOCRVLRuntime {
        let config = try loadConfig(from: modelDirectory)
        let model = PaddleOCRVLModel(config: config)

        if let (bits, groupSize) = readQuantizationConfig(from: modelDirectory) {
            MLXNN.quantize(model: model, groupSize: groupSize, bits: bits)
        }

        try loadWeights(into: model, from: modelDirectory)

        let tokenizer = try await AutoTokenizer.from(modelFolder: modelDirectory)
        let imageProcessor = PaddleOCRVLImageProcessor(mode: .base)
        let generator = PaddleOCRVLGenerator(model: model, tokenizer: tokenizer, config: config)
        return PaddleOCRVLRuntime(imageProcessor: imageProcessor, generator: generator)
    }

    // jzhang533/PaddleOCR-VL-For-Manga stores text model params at the top level of
    // config.json with no "text_config" sub-key. paddleocr-vl.swift falls back to wrong
    // defaults (vocabSize=48000, hiddenSize=896). We read top-level keys instead.
    private static func loadConfig(from directory: URL) throws -> PaddleOCRVLConfig {
        let data = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return try PaddleOCRVLConfig.load(from: directory)
        }

        let textConfigDict = raw["text_config"] as? [String: Any] ?? [:]
        let visionConfigDict = raw["vision_config"] as? [String: Any] ?? [:]

        let textConfig = PaddleOCRVLTextConfig(
            vocabSize: (textConfigDict["vocab_size"] as? Int) ?? (raw["vocab_size"] as? Int) ?? 48000,
            hiddenSize: (textConfigDict["hidden_size"] as? Int) ?? (raw["hidden_size"] as? Int) ?? 896,
            intermediateSize: (textConfigDict["intermediate_size"] as? Int) ?? (raw["intermediate_size"] as? Int) ?? 4864,
            numHiddenLayers: (textConfigDict["num_hidden_layers"] as? Int) ?? (raw["num_hidden_layers"] as? Int) ?? 24,
            numAttentionHeads: (textConfigDict["num_attention_heads"] as? Int) ?? (raw["num_attention_heads"] as? Int) ?? 14,
            numKeyValueHeads: (textConfigDict["num_key_value_heads"] as? Int) ?? (raw["num_key_value_heads"] as? Int) ?? 2,
            rmsNormEps: (textConfigDict["rms_norm_eps"] as? Float) ?? (raw["rms_norm_eps"] as? Float) ?? 1e-6,
            ropeTheta: (textConfigDict["rope_theta"] as? Float) ?? (raw["rope_theta"] as? Float) ?? 10_000
        )
        let visionConfig = PaddleOCRVLVisionConfig(
            hiddenSize: (visionConfigDict["hidden_size"] as? Int) ?? 1024,
            numHiddenLayers: (visionConfigDict["num_hidden_layers"] as? Int) ?? 24,
            numAttentionHeads: (visionConfigDict["num_attention_heads"] as? Int) ?? 16,
            numChannels: (visionConfigDict["num_channels"] as? Int) ?? 3,
            imageSize: (visionConfigDict["image_size"] as? Int) ?? 448,
            patchSize: (visionConfigDict["patch_size"] as? Int) ?? 14,
            layerNormEps: (visionConfigDict["layer_norm_eps"] as? Float) ?? 1e-6,
            intermediateSize: (visionConfigDict["intermediate_size"] as? Int) ?? 4096
        )

        return PaddleOCRVLConfig(
            visionConfig: visionConfig,
            textConfig: textConfig,
            imageTokenIndex: (raw["image_token_id"] as? Int) ?? (raw["image_token_index"] as? Int) ?? 151655,
            visionStartTokenId: (raw["vision_start_token_id"] as? Int) ?? 151652,
            visionEndTokenId: (raw["vision_end_token_id"] as? Int) ?? 151653,
            visionTokenId: (raw["image_token_id"] as? Int) ?? 151654
        )
    }

    private static func readQuantizationConfig(from directory: URL) -> (bits: Int, groupSize: Int)? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("config.json")),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let q = raw["quantization"] as? [String: Any],
              let bits = q["bits"] as? Int,
              let groupSize = q["group_size"] as? Int else { return nil }
        return (bits, groupSize)
    }

    // Key remapping for jzhang533/PaddleOCR-VL-For-Manga → paddleocr-vl.swift schema:
    //   language_model.model.*        → model.*
    //   language_model.lm_head.*      → lm_head.*
    //   visual.*                      → vision_model.*
    //   vision_model.embeddings.patch_embedding.* → vision_model.patch_embed.proj.*
    //   vision_model.layers.N.self_attn.out_proj.* → vision_model.layers.N.self_attn.proj.*
    //   vision_model.projector.*      → multi_modal_projector.*
    //   (drop) embeddings.position_embedding.*  — stored as internal var, set via zeros
    //   (drop) multi_modal_projector.pre_norm.* — not in MultiModalProjector
    private static func loadWeights(into model: PaddleOCRVLModel, from directory: URL) throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw PaddleOCREngineError.modelUnavailable }

        var all: [String: MLXArray] = [:]
        for f in files {
            let w = try MLX.loadArrays(url: f)
            all.merge(w) { _, new in new }
        }

        var sanitized: [String: MLXArray] = [:]
        for (key, value) in all {
            if key.contains("rotary_emb.inv_freq") { continue }
            if key.contains("embeddings.position_embedding") { continue }

            var k = key
            var v = value

            // language_model.model.* / language_model.lm_head.*
            if k.hasPrefix("language_model.") {
                k = String(k.dropFirst("language_model.".count))
            }

            // visual.* → vision_model.*
            if k.hasPrefix("visual.") {
                k = "vision_model." + k.dropFirst("visual.".count)
            }

            // vision_model.embeddings.patch_embedding.* → vision_model.patch_embed.proj.*
            if k.hasPrefix("vision_model.embeddings.patch_embedding.") {
                k = "vision_model.patch_embed.proj." + k.dropFirst("vision_model.embeddings.patch_embedding.".count)
            }

            // vision_model.layers.N.self_attn.out_proj → vision_model.layers.N.self_attn.proj
            k = k.replacingOccurrences(of: ".self_attn.out_proj", with: ".self_attn.proj")

            // vision_model.projector.* → multi_modal_projector.*
            if k.hasPrefix("vision_model.projector.") {
                k = "multi_modal_projector." + k.dropFirst("vision_model.projector.".count)
            }

            // drop projector pre_norm (not in MultiModalProjector)
            if k.hasPrefix("multi_modal_projector.pre_norm") { continue }

            // transpose 4-D conv weights from NCHW → NHWC
            if k.contains("patch_embed") && k.hasSuffix(".weight") && v.ndim == 4 {
                let s = v.shape
                if s[1] != s[2] && s[2] == s[3] { v = v.transposed(0, 2, 3, 1) }
            }

            sanitized[k] = v
        }

        let parameters = ModuleParameters.unflattened(sanitized)
        // .none: keys that don't match are silently skipped rather than throwing
        try model.update(parameters: parameters, verify: .none)
    }

    private static func runBlocking<T>(_ op: @escaping () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        Task.detached {
            do { result = .success(try await op()) }
            catch { result = .failure(error) }
            sem.signal()
        }
        sem.wait()
        return try result!.get()
    }
}

// MARK: - Engine errors

public enum PaddleOCREngineError: Error, Equatable {
    case modelUnavailable
    case invalidInputImage
    case runtimeFailure(String)
}

extension PaddleOCREngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "PaddleOCR model artifacts are unavailable."
        case .invalidInputImage: return "Input image is invalid."
        case .runtimeFailure(let m): return "PaddleOCR runtime failed: \(m)"
        }
    }
}

private extension DefaultPaddleOCREngine {
    static func hasRequiredArtifacts(in directory: URL) -> Bool {
        let fm = FileManager.default
        let required = ["config.json", "generation_config.json", "tokenizer.json",
                        "tokenizer_config.json", "special_tokens_map.json"]
        for name in required {
            guard fm.fileExists(atPath: directory.appendingPathComponent(name).path) else { return false }
        }
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        return files.contains { $0.pathExtension == "safetensors" }
    }
}
#endif
