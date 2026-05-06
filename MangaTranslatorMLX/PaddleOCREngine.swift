import Foundation
import AppKit
import CoreImage
import os

#if arch(arm64)
import MLX
import MLXNN
import MLXFast
import Metal
import PaddleOCRVL
import Tokenizers
import Hub

// MARK: - Inference engine protocol (for testability)

public protocol PaddleOCRInferencing: AnyObject {
    func infer(image: CGImage) throws -> (text: String, confidence: Float)
}

struct PaddleOCRDebugTrace {
    let rawText: String
    let trimmedText: String
    let generatedTokens: [Int]
    let terminationToken: Int?
    let firstStepTopTokens: [PaddleOCRDebugToken]
}

struct PaddleOCRDebugToken {
    let tokenId: Int
    let logit: Float
}

struct PaddleOCRPrefillDebug {
    let pixelValues: MLXArray
    let encodedVisionFeatures: MLXArray
    let projectedImageFeatures: MLXArray
    let mergedEmbeddings: MLXArray
    let firstLayerInputNormLastToken: MLXArray
    let firstLayerAttentionOutputLastToken: MLXArray
    let firstLayerAttentionRawQueriesLastToken: MLXArray
    let firstLayerAttentionRawKeysLastToken: MLXArray
    let firstLayerAttentionRawValuesLastToken: MLXArray
    let firstLayerAttentionQueriesLastToken: MLXArray
    let firstLayerAttentionKeysLastToken: MLXArray
    let firstLayerAttentionValuesLastToken: MLXArray
    let firstLayerAttentionWeightsLastRow: MLXArray
    let firstLayerResidualAfterAttentionLastToken: MLXArray
    let firstLayerPostAttentionNormLastToken: MLXArray
    let firstLayerMLPOutputLastToken: MLXArray
    let firstLayerOutputLastToken: MLXArray
    let layerLastTokenHiddenStates: [MLXArray]
    let firstStepLogits: MLXArray
    let inputIds: [Int]
    let targetWidth: Int
    let targetHeight: Int
}

// MARK: - Rotary PE helpers

private func rotateHalfVision(_ x: MLXArray) -> MLXArray {
    let half = x.dim(-1) / 2
    let x1 = x[.ellipsis, ..<half]
    let x2 = x[.ellipsis, half...]
    return concatenated([-x2, x1], axis: -1)
}

private func applyRotaryPosEmbVision(_ tensor: MLXArray, freqs: MLXArray) -> MLXArray {
    let origDtype = tensor.dtype
    let freqsF = freqs.asType(.float32)
    // cos/sin: (N, 36)
    var cosF = MLX.cos(freqsF)
    var sinF = MLX.sin(freqsF)
    // → (N, 1, 36) → (N, 1, 72) → (1, N, 1, 72)
    cosF = cosF.expandedDimensions(axis: 1)
    cosF = concatenated([cosF, cosF], axis: -1)
    cosF = cosF.expandedDimensions(axis: 0)
    sinF = sinF.expandedDimensions(axis: 1)
    sinF = concatenated([sinF, sinF], axis: -1)
    sinF = sinF.expandedDimensions(axis: 0)
    let t = tensor.asType(.float32)
    return ((t * cosF) + (rotateHalfVision(t) * sinF)).asType(origDtype)
}

// MARK: - Manga Vision Encoder (jzhang533/PaddleOCR-VL-For-Manga architecture)

private class MangaVisionAttention: Module {
    @ModuleInfo(key: "qkv") var qkv: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    let numHeads: Int
    let headDim: Int
    let scale: Float

    init(hiddenSize: Int, numHeads: Int) {
        self.numHeads = numHeads
        self.headDim = hiddenSize / numHeads
        self.scale = pow(Float(hiddenSize / numHeads), -0.5)
        self._qkv.wrappedValue = Linear(hiddenSize, hiddenSize * 3, bias: true)
        self._outProj.wrappedValue = Linear(hiddenSize, hiddenSize, bias: true)
        super.init()
    }

    func callAsFunction(_ x: MLXArray, rotaryPosEmb: MLXArray) -> MLXArray {
        let N = x.dim(0)  // seq_length, no batch dim
        // (N, 3*dim) → (N, 3, heads, head_dim) → (3, N, heads, head_dim)
        let qkvOut = qkv(x).reshaped(N, 3, numHeads, headDim).transposed(1, 0, 2, 3)
        let parts = split(qkvOut, parts: 3, axis: 0)  // 3 × (1, N, heads, head_dim)
        var q = parts[0]
        var k = parts[1]
        let v = parts[2]

        // Apply 2D rotary PE: expand to (1, 1, N, heads, head_dim), apply, index back
        q = applyRotaryPosEmbVision(q.expandedDimensions(axis: 0), freqs: rotaryPosEmb)[0]
        k = applyRotaryPosEmbVision(k.expandedDimensions(axis: 0), freqs: rotaryPosEmb)[0]

        // (1, N, heads, head_dim) → (1, heads, N, head_dim) for SDPA
        let qT = q.transposed(0, 2, 1, 3)
        let kT = k.transposed(0, 2, 1, 3)
        let vT = v.transposed(0, 2, 1, 3)

        var out = MLXFast.scaledDotProductAttention(
            queries: qT, keys: kT, values: vT, scale: scale, mask: .none
        )
        out = out.transposed(0, 2, 1, 3).reshaped(N, -1)
        return outProj(out)
    }
}

private class MangaVisionMLP: Module {
    @ModuleInfo(key: "fc1") var fc1: Linear
    @ModuleInfo(key: "fc2") var fc2: Linear

    init(hiddenSize: Int, intermediateSize: Int) {
        self._fc1.wrappedValue = Linear(hiddenSize, intermediateSize, bias: true)
        self._fc2.wrappedValue = Linear(intermediateSize, hiddenSize, bias: true)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        fc2(geluApproximate(fc1(x)))
    }
}

private class MangaVisionEncoderLayer: Module {
    @ModuleInfo(key: "layer_norm1") var layerNorm1: LayerNorm
    @ModuleInfo(key: "self_attn") var selfAttn: MangaVisionAttention
    @ModuleInfo(key: "layer_norm2") var layerNorm2: LayerNorm
    @ModuleInfo(key: "mlp") var mlp: MangaVisionMLP

    init(hiddenSize: Int, numHeads: Int, intermediateSize: Int) {
        self._layerNorm1.wrappedValue = LayerNorm(dimensions: hiddenSize, eps: 1e-6)
        self._selfAttn.wrappedValue = MangaVisionAttention(hiddenSize: hiddenSize, numHeads: numHeads)
        self._layerNorm2.wrappedValue = LayerNorm(dimensions: hiddenSize, eps: 1e-6)
        self._mlp.wrappedValue = MangaVisionMLP(hiddenSize: hiddenSize, intermediateSize: intermediateSize)
        super.init()
    }

    func callAsFunction(_ x: MLXArray, rotaryPosEmb: MLXArray) -> MLXArray {
        let h = x + selfAttn(layerNorm1(x), rotaryPosEmb: rotaryPosEmb)
        return h + mlp(layerNorm2(h))
    }
}

private class MangaVisionEmbeddings: Module {
    @ModuleInfo(key: "patch_embedding") var patchEmbedding: Conv2d
    @ModuleInfo(key: "position_embedding") var positionEmbedding: Embedding

    let sqrtBase: Int   // imageSize / patchSize = 27
    let numPatchesBase: Int  // 27*27 = 729
    let hiddenSize: Int

    init(patchSize: Int, imageSize: Int, hiddenSize: Int) {
        self.hiddenSize = hiddenSize
        self.sqrtBase = imageSize / patchSize  // 384/14 = 27
        self.numPatchesBase = (imageSize / patchSize) * (imageSize / patchSize)  // 729
        self._patchEmbedding.wrappedValue = Conv2d(
            inputChannels: 3,
            outputChannels: hiddenSize,
            kernelSize: IntOrPair(patchSize),
            stride: IntOrPair(patchSize)
        )
        self._positionEmbedding.wrappedValue = Embedding(embeddingCount: numPatchesBase, dimensions: hiddenSize)
        super.init()
    }

    // Bilinear interpolation matching Python's bilinear_interpolate(align_corners=False)
    private func bilinearInterp(_ emb: MLXArray, targetH: Int, targetW: Int) -> MLXArray {
        let Hin = emb.dim(0), Win = emb.dim(1), D = emb.dim(2)
        if targetH == Hin && targetW == Win {
            return emb.reshaped(Hin * Win, D)
        }
        // Sampling positions: (i + 0.5) * H_in / new_H - 0.5
        let rowF = (MLXArray(Array(0..<targetH).map { Float($0) }) + 0.5) * (Float(Hin) / Float(targetH)) - 0.5
        let colF = (MLXArray(Array(0..<targetW).map { Float($0) }) + 0.5) * (Float(Win) / Float(targetW)) - 0.5

        let rFloor = MLX.clip(MLX.floor(rowF).asType(.int32), min: Int32(0), max: Int32(Hin - 1))
        let cFloor = MLX.clip(MLX.floor(colF).asType(.int32), min: Int32(0), max: Int32(Win - 1))
        let rCeil  = MLX.clip(rFloor + 1, min: Int32(0), max: Int32(Hin - 1))
        let cCeil  = MLX.clip(cFloor + 1, min: Int32(0), max: Int32(Win - 1))

        let rw = (rowF - rFloor.asType(.float32)).reshaped(targetH, 1, 1)
        let cw = (colF - cFloor.asType(.float32)).reshaped(1, targetW, 1)

        let flat = emb.reshaped(Hin * Win, D)

        func gather(_ r: MLXArray, _ c: MLXArray) -> MLXArray {
            let idx = (r.reshaped(targetH, 1) * Int32(Win) + c.reshaped(1, targetW)).reshaped(-1)
            return flat[idx].reshaped(targetH, targetW, D)
        }

        let tl = gather(rFloor, cFloor), tr = gather(rFloor, cCeil)
        let bl = gather(rCeil,  cFloor), br = gather(rCeil,  cCeil)

        let result = (1 - rw) * (1 - cw) * tl + (1 - rw) * cw * tr
                   + rw * (1 - cw) * bl + rw * cw * br
        return result.reshaped(targetH * targetW, D)
    }

    private func interpolatePosEncoding(h: Int, w: Int) -> MLXArray {
        let ids = MLXArray(Array(0..<numPatchesBase).map { Int32($0) })
        let base = positionEmbedding(ids)  // (729, 1152) — dequantizes if quantized
        let grid = base.asType(.float32).reshaped(sqrtBase, sqrtBase, hiddenSize)
        return bilinearInterp(grid, targetH: h, targetW: w).asType(base.dtype)
    }

    func callAsFunction(_ pixelValues: MLXArray, h: Int, w: Int) -> MLXArray {
        // pixelValues: (1, H, W, 3) NHWC
        let patches = patchEmbedding(pixelValues).reshaped(h * w, hiddenSize)  // (N, dim)
        let posEmb = interpolatePosEncoding(h: h, w: w)  // (N, dim)
        return patches + posEmb
    }
}

private class MangaVisionEncoder: Module {
    @ModuleInfo(key: "embeddings") var embeddings: MangaVisionEmbeddings
    @ModuleInfo(key: "layers") var layers: [MangaVisionEncoderLayer]
    @ModuleInfo(key: "post_layernorm") var postLayerNorm: LayerNorm

    let rotaryDim: Int   // head_dim / 2 = 36
    let rotaryTheta: Float = 10000.0

    init(hiddenSize: Int, numHeads: Int, numLayers: Int, patchSize: Int,
         imageSize: Int, intermediateSize: Int, layerNormEps: Float) {
        let headDim = hiddenSize / numHeads
        self.rotaryDim = headDim / 2

        self._embeddings.wrappedValue = MangaVisionEmbeddings(
            patchSize: patchSize, imageSize: imageSize, hiddenSize: hiddenSize)
        self._layers.wrappedValue = (0..<numLayers).map { _ in
            MangaVisionEncoderLayer(hiddenSize: hiddenSize, numHeads: numHeads,
                                    intermediateSize: intermediateSize)
        }
        self._postLayerNorm.wrappedValue = LayerNorm(dimensions: hiddenSize, eps: layerNormEps)
        super.init()
    }

    // Compute 2D rotary frequencies for a (t, h, w) patch grid.
    // Returns (t*h*w, rotaryDim*2) where rotaryDim*2 = head_dim = 72.
    private func computeRotaryFreqs(t: Int, h: Int, w: Int) -> MLXArray {
        // inv_freq: (18,) via theta^(-arange/rotaryDim)
        let arangeVals = MLXArray(Array(stride(from: 0, to: rotaryDim, by: 2)).map { Float($0) })
        let invFreq = MLX.exp(-log(rotaryTheta) * arangeVals / Float(rotaryDim)).asType(.float32)

        let maxGrid = max(h, w)
        let seqVals = MLXArray(Array(0..<maxGrid).map { Float($0) })
        let fullFreqs = seqVals.reshaped(-1, 1) * invFreq.reshaped(1, -1)  // (maxGrid, 18)

        let N = t * h * w
        let hwSize = h * w
        // Row/col index for each patch
        let hIds = MLXArray(Array(0..<N).map { Int32(($0 % hwSize) / w) })
        let wIds = MLXArray(Array(0..<N).map { Int32(($0 % hwSize) % w) })

        let hFreqs = fullFreqs[hIds]  // (N, 18)
        let wFreqs = fullFreqs[wIds]  // (N, 18)
        return concatenated([hFreqs, wFreqs], axis: -1)  // (N, 36)
    }

    func callAsFunction(_ pixelValues: MLXArray, t: Int, h: Int, w: Int) -> MLXArray {
        var x = embeddings(pixelValues, h: h, w: w)  // (N, hidden)
        let rotaryPosEmb = computeRotaryFreqs(t: t, h: h, w: w)  // (N, 36)

        for layer in layers {
            x = layer(x, rotaryPosEmb: rotaryPosEmb)
        }
        x = postLayerNorm(x)
        return x.expandedDimensions(axis: 0)  // (1, N, hidden) to match projector input
    }
}

// MARK: - Custom Projector (Patch Merging)

private class MangaMultiModalProjector: Module {
    @ModuleInfo(key: "preNorm") var preNorm: LayerNorm
    @ModuleInfo(key: "linear1") var linear1: Linear
    @ModuleInfo(key: "linear2") var linear2: Linear

    let inputDim: Int

    public init(config: PaddleOCRVLConfig) {
        self.inputDim = config.visionConfig.hiddenSize
        let mergedDim = self.inputDim * 4
        self._preNorm.wrappedValue = LayerNorm(dimensions: inputDim, eps: 1e-5)
        self._linear1.wrappedValue = Linear(mergedDim, mergedDim, bias: true)
        self._linear2.wrappedValue = Linear(mergedDim, config.textConfig.hiddenSize, bias: true)
        super.init()
    }

    public func callAsFunction(_ features: MLXArray, height: Int, width: Int, patchSize: Int) -> MLXArray {
        var x = preNorm(features)

        let batch = x.dim(0)
        let hPatches = height / patchSize
        let wPatches = width / patchSize

        x = x.reshaped(batch, hPatches, wPatches, inputDim)

        let hMerged = hPatches / 2
        let wMerged = wPatches / 2

        x = x.reshaped(batch, hMerged, 2, wMerged, 2, inputDim)
        x = x.transposed(0, 1, 3, 2, 4, 5)
        x = x.reshaped(batch, hMerged * wMerged, inputDim * 4)

        x = linear1(x)
        x = gelu(x)
        x = linear2(x)

        return x
    }
}

// MARK: - Subcomponents for OCR Engine

private struct ImagePreprocessor {
    let context: CIContext

    func preprocessFullImage(_ ciImage: CIImage, targetWidth: Int, targetHeight: Int) -> MLXArray {
        let extent = ciImage.extent
        let scaleX = CGFloat(targetWidth) / extent.width
        let scaleY = CGFloat(targetHeight) / extent.height
        let scaled = ciImage
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var data = Data(count: targetWidth * targetHeight * 4)
        data.withUnsafeMutableBytes { ptr in
            context.render(
                scaled,
                toBitmap: ptr.baseAddress!,
                rowBytes: targetWidth * 4,
                bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        let uint8Array = MLXArray(data, [targetHeight, targetWidth, 4], type: UInt8.self)
        var px = uint8Array.asType(.float32) / 255.0
        px = px[0..., 0..., ..<3]
        px = (px - 0.5) / 0.5
        return px.reshaped(1, targetHeight, targetWidth, 3).asType(.bfloat16)
    }

    func preprocessTile(_ ciImage: CIImage, rect: CGRect, targetSize: Int) -> MLXArray {
        let tileImage = ciImage
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(targetSize) / rect.width, y: CGFloat(targetSize) / rect.height))
            .cropped(to: CGRect(origin: .zero, size: CGSize(width: targetSize, height: targetSize)))

        var data = Data(count: targetSize * targetSize * 4)
        data.withUnsafeMutableBytes { ptr in
            context.render(
                tileImage,
                toBitmap: ptr.baseAddress!,
                rowBytes: targetSize * 4,
                bounds: tileImage.extent,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        let uint8Array = MLXArray(data, [targetSize, targetSize, 4], type: UInt8.self)
        var px = uint8Array.asType(.float32) / 255.0
        px = px[0..., 0..., ..<3]
        px = (px - 0.5) / 0.5
        return px.reshaped(1, targetSize, targetSize, 3).asType(.bfloat16)
    }
}

private struct TokenizerAdapter {
    let tokenizer: any Tokenizer
    let config: PaddleOCRVLConfig

    var stopTokens: Set<Int> {
        let eosId = tokenizer.eosTokenId ?? 2
        return [2, 100272, eosId]
    }

    func buildInputIds(numMergedTokens: Int, textPrompt: String? = nil) -> [Int] {
        let prompt = textPrompt ?? "OCR:"
        let userPrefixIds = tokenizer.encode(text: "User: ", addSpecialTokens: false)
        let textIds = tokenizer.encode(text: prompt + "\nAssistant: ", addSpecialTokens: false)

        var inputIds: [Int] = []
        inputIds.append(100273)  // <|begin_of_sentence|>
        inputIds.append(contentsOf: userPrefixIds)
        inputIds.append(config.visionStartTokenId)
        inputIds.append(contentsOf: Array(repeating: config.visionTokenId, count: numMergedTokens))
        inputIds.append(config.visionEndTokenId)
        inputIds.append(contentsOf: textIds)
        return inputIds
    }

    func decode(_ tokens: [Int]) -> String {
        tokenizer.decode(tokens: tokens, skipSpecialTokens: true)
    }
}

private struct GeneratorRuntime {
    struct GenerationTrace {
        let generatedTokens: [Int]
        let terminationToken: Int?
        let firstStepTopTokens: [PaddleOCRDebugToken]
    }

    struct GenerationSettings {
        let maxNewTokens: Int
        let noRepeatNgramSize: Int
    }

    let model: PaddleOCRVLModel
    let stopTokens: Set<Int>
    let settings: GenerationSettings

    func generate(imageFeatures: MLXArray, inputIds: [Int], maxNewTokens: Int) -> [Int] {
        generateTrace(imageFeatures: imageFeatures, inputIds: inputIds, maxNewTokens: maxNewTokens).generatedTokens
    }

    func generateTrace(imageFeatures: MLXArray, inputIds: [Int], maxNewTokens: Int) -> GenerationTrace {
        var inputIdArray = MLXArray(inputIds.map { Int32($0) }).reshaped(1, -1)
        let cache = model.newCache()

        let mergedEmbeds = model.mergeInputIdsWithImageFeatures(inputIds: inputIdArray, imageFeatures: imageFeatures)
        let hiddenStates = model.languageModel.forward(mergedEmbeds, cache: cache)
        var logits = model.lmHead(hiddenStates)

        var generatedTokens: [Int] = []
        let tokenBudget = effectiveMaxNewTokens(requested: maxNewTokens, configured: settings.maxNewTokens)
        var terminationToken: Int?
        var firstStepTopTokens: [PaddleOCRDebugToken] = []

        for step in 0..<tokenBudget {
            let lastLogits = logits[0, -1]
            if step == 0 {
                firstStepTopTokens = topTokens(from: lastLogits, count: 5)
            }
            let nextTokenId = argMax(lastLogits).item(Int.self)

            if stopTokens.contains(nextTokenId) {
                terminationToken = nextTokenId
                break
            }
            if wouldRepeatNgram(
                generatedTokens: generatedTokens,
                nextTokenId: nextTokenId,
                noRepeatNgramSize: settings.noRepeatNgramSize
            ) {
                terminationToken = nextTokenId
                break
            }

            generatedTokens.append(nextTokenId)

            if detectLoop(in: generatedTokens) {
                terminationToken = nextTokenId
                break
            }

            inputIdArray = MLXArray([Int32(nextTokenId)]).reshaped(1, 1)
            let nextEmbeds = model.languageModel.getEmbedding(inputIdArray)
            let nextHidden = model.languageModel.forward(nextEmbeds, cache: cache)
            logits = model.lmHead(nextHidden)

            eval(logits)
            for c in cache { if let cs = c as? (any Updatable) { eval(cs) } }
        }
        return GenerationTrace(
            generatedTokens: generatedTokens,
            terminationToken: terminationToken,
            firstStepTopTokens: firstStepTopTokens
        )
    }

    private func detectLoop(in tokens: [Int]) -> Bool {
        for n in 1...4 {
            if tokens.count >= n * 3 {
                let tail = Array(tokens.suffix(n))
                let prev = Array(tokens.dropLast(n).suffix(n))
                let prevPrev = Array(tokens.dropLast(n * 2).suffix(n))
                if tail == prev && prev == prevPrev {
                    return true
                }
            }
        }
        return false
    }

    private func topTokens(from logits: MLXArray, count: Int) -> [PaddleOCRDebugToken] {
        let sortedIndices = argSort(logits).asArray(Int32.self)
        let topIndices = Array(sortedIndices.suffix(count).reversed()).map(Int.init)
        return topIndices.map { tokenId in
            PaddleOCRDebugToken(
                tokenId: tokenId,
                logit: logits[tokenId].item(Float.self)
            )
        }
    }
}

func effectiveMaxNewTokens(requested: Int, configured: Int) -> Int {
    max(1, min(requested, configured))
}

func wouldRepeatNgram(generatedTokens: [Int], nextTokenId: Int, noRepeatNgramSize: Int) -> Bool {
    guard noRepeatNgramSize > 1 else { return false }
    let prefixSize = noRepeatNgramSize - 1
    guard generatedTokens.count >= prefixSize else { return false }

    let prefix = Array(generatedTokens.suffix(prefixSize))
    let candidate = prefix + [nextTokenId]
    guard generatedTokens.count >= noRepeatNgramSize else { return false }

    for start in 0...(generatedTokens.count - noRepeatNgramSize) {
        if Array(generatedTokens[start..<(start + noRepeatNgramSize)]) == candidate {
            return true
        }
    }
    return false
}

private struct PaddleOCRGenerationConfig: Decodable {
    let maxLength: Int?
    let noRepeatNgramSize: Int?

    enum CodingKeys: String, CodingKey {
        case maxLength = "max_length"
        case noRepeatNgramSize = "no_repeat_ngram_size"
    }
}

// MARK: - Internal runtime container

private struct PaddleOCRVLRuntime {
    let model: PaddleOCRVLModel
    let visionEncoder: MangaVisionEncoder
    let projector: MangaMultiModalProjector
    let tokenizerAdapter: TokenizerAdapter
    let imagePreprocessor: ImagePreprocessor
    let generator: GeneratorRuntime
    let config: PaddleOCRVLConfig
    let numVisionLayers: Int

    func recognize(ciImage: CIImage) -> String {
        recognizeDebug(ciImage: ciImage).trimmedText
    }

    func recognizeDebug(ciImage: CIImage, promptOverride: String? = nil) -> PaddleOCRDebugTrace {
        let patchSize = config.visionConfig.patchSize
        let hiddenSize = config.visionConfig.hiddenSize
        let srcW = Int(ciImage.extent.width)
        let srcH = Int(ciImage.extent.height)

        let availableMemory = availableGPUMemoryBytes()
        if shouldUseSmartResize(srcW: srcW, srcH: srcH, patchSize: patchSize,
                                 hiddenSize: hiddenSize, numLayers: numVisionLayers,
                                 availableMemoryBytes: availableMemory) {
            let (targetW, targetH) = smartResizeClampedDimensions(srcW: srcW, srcH: srcH, patchSize: patchSize)
            return recognizeSmartResizeDebug(ciImage: ciImage, targetW: targetW, targetH: targetH, promptOverride: promptOverride)
        } else {
            return recognizeTiledDebug(ciImage: ciImage, promptOverride: promptOverride)
        }
    }


    private func recognizeSmartResize(ciImage: CIImage, targetW: Int, targetH: Int) -> String {
        recognizeSmartResizeDebug(ciImage: ciImage, targetW: targetW, targetH: targetH, promptOverride: nil).trimmedText
    }

    private func recognizeSmartResizeDebug(ciImage: CIImage, targetW: Int, targetH: Int, promptOverride: String?) -> PaddleOCRDebugTrace {
        let patchSize = config.visionConfig.patchSize
        let hPatches = targetH / patchSize
        let wPatches = targetW / patchSize
        let pixelValues = imagePreprocessor.preprocessFullImage(ciImage, targetWidth: targetW, targetHeight: targetH)
        let visionFeatures = visionEncoder(pixelValues, t: 1, h: hPatches, w: wPatches)
        let projected = projector(visionFeatures, height: targetH, width: targetW, patchSize: patchSize)

        let inputIds = tokenizerAdapter.buildInputIds(numMergedTokens: projected.dim(1), textPrompt: promptOverride)
        let generationTrace = generator.generateTrace(imageFeatures: projected, inputIds: inputIds, maxNewTokens: 1024)
        let generatedTokens = generationTrace.generatedTokens
        let rawText = tokenizerAdapter.decode(generatedTokens)
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            print("[PaddleOCREngine] Warning: Empty OCR result from smart_resize path. Tokens: \(generatedTokens)")
        }
        return PaddleOCRDebugTrace(
            rawText: rawText,
            trimmedText: trimmedText,
            generatedTokens: generatedTokens,
            terminationToken: generationTrace.terminationToken,
            firstStepTopTokens: generationTrace.firstStepTopTokens
        )
    }

    private func recognizeTiled(ciImage: CIImage) -> String {
        recognizeTiledDebug(ciImage: ciImage, promptOverride: nil).trimmedText
    }

    private func recognizeTiledDebug(ciImage: CIImage, promptOverride: String?) -> PaddleOCRDebugTrace {
        let patchSize = config.visionConfig.patchSize  // 14
        let tileSize = 392  // 28 patches per side → 14×14 merged tokens per tile
        let srcW = Int(ciImage.extent.width)
        let srcH = Int(ciImage.extent.height)

        let maxTilesX = 3
        let maxTilesY = 4
        let tilesX = max(1, min(maxTilesX, Int(round(Double(srcW) / Double(tileSize)))))
        let tilesY = max(1, min(maxTilesY, Int(round(Double(srcH) / Double(tileSize)))))
        let tileW = CGFloat(srcW) / CGFloat(tilesX)
        let tileH = CGFloat(srcH) / CGFloat(tilesY)

        let hPatches = tileSize / patchSize  // 28
        let wPatches = tileSize / patchSize  // 28

        var allProjectedFeatures: [MLXArray] = []
        for row in 0..<tilesY {
            for col in 0..<tilesX {
                let cropRect = CGRect(
                    x: CGFloat(col) * tileW, y: CGFloat(row) * tileH,
                    width: tileW, height: tileH
                )
                let pixelValues = imagePreprocessor.preprocessTile(ciImage, rect: cropRect, targetSize: tileSize)
                let visionFeatures = visionEncoder(pixelValues, t: 1, h: hPatches, w: wPatches)
                let projected = projector(visionFeatures, height: tileSize, width: tileSize, patchSize: patchSize)
                allProjectedFeatures.append(projected)
            }
        }
        let mergedFeatures = allProjectedFeatures.count == 1
            ? allProjectedFeatures[0]
            : concatenated(allProjectedFeatures, axis: 1)

        let inputIds = tokenizerAdapter.buildInputIds(numMergedTokens: mergedFeatures.dim(1), textPrompt: promptOverride)
        let generationTrace = generator.generateTrace(imageFeatures: mergedFeatures, inputIds: inputIds, maxNewTokens: 1024)
        let generatedTokens = generationTrace.generatedTokens
        let rawText = tokenizerAdapter.decode(generatedTokens)
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            print("[PaddleOCREngine] Warning: Empty OCR result from tiling path. Tokens: \(generatedTokens)")
        }
        return PaddleOCRDebugTrace(
            rawText: rawText,
            trimmedText: trimmedText,
            generatedTokens: generatedTokens,
            terminationToken: generationTrace.terminationToken,
            firstStepTopTokens: generationTrace.firstStepTopTokens
        )
    }
}

// MARK: - Smart-resize routing helpers (internal for testability)

/// Compute smart_resize target dimensions with max_pixels cap, matching Python image_processing.py.
func smartResizeClampedDimensions(srcW: Int, srcH: Int, patchSize: Int) -> (targetW: Int, targetH: Int) {
    let factor = patchSize * 2  // spatialMergeSize = 2 → 28
    let maxPixels = 28 * 28 * 1280  // 1,003,520 — Python default

    var targetH = max(factor, Int(round(Double(srcH) / Double(factor))) * factor)
    var targetW = max(factor, Int(round(Double(srcW) / Double(factor))) * factor)

    if targetH * targetW > maxPixels {
        let beta = sqrt(Double(srcH * srcW) / Double(maxPixels))
        targetH = max(factor, Int(floor(Double(srcH) / beta / Double(factor))) * factor)
        targetW = max(factor, Int(floor(Double(srcW) / beta / Double(factor))) * factor)
    }
    return (targetW, targetH)
}

/// Returns whether smart_resize (single-tile, aspect-ratio-preserving) should be used
/// instead of fixed tiling.
///
/// MLX uses flash attention (SDPA), so the attention matrix is never fully materialised —
/// peak memory scales linearly with patch count, not quadratically.
/// The ×10 multiplier budgets Q/K/V activations, layer-norms, and residuals.
func shouldUseSmartResize(
    srcW: Int, srcH: Int,
    patchSize: Int, hiddenSize: Int, numLayers: Int,
    availableMemoryBytes: Int
) -> Bool {
    let (targetW, targetH) = smartResizeClampedDimensions(srcW: srcW, srcH: srcH, patchSize: patchSize)
    let numPatches = (targetH / patchSize) * (targetW / patchSize)
    let peakMemoryD = Double(numPatches) * Double(hiddenSize) * Double(numLayers) * 2.0 * 10.0
    return peakMemoryD < Double(availableMemoryBytes) * 0.8
}

private func availableGPUMemoryBytes() -> Int {
    if let device = MTLCreateSystemDefaultDevice() {
        return Int(device.recommendedMaxWorkingSetSize)
    }
    return 8 * 1024 * 1024 * 1024  // 8 GB fallback
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
        let text = rt.recognize(ciImage: ciImage)
        let confidence: Float = text.isEmpty ? 0 : 1
        return (text, confidence)
    }

    func inferDebug(image: CGImage, promptOverride: String? = nil) throws -> PaddleOCRDebugTrace {
        guard image.width > 0 && image.height > 0 else {
            throw PaddleOCREngineError.invalidInputImage
        }
        let rt = try loadRuntimeIfNeeded()
        let ciImage = CIImage(cgImage: image)
        return rt.recognizeDebug(ciImage: ciImage, promptOverride: promptOverride)
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

    private static func buildRuntime(modelDirectory: URL) async throws -> PaddleOCRVLRuntime {
        let config = try loadConfig(from: modelDirectory)
        let visionNumLayers = try readVisionNumLayers(from: modelDirectory)
        let generationSettings = readGenerationSettings(from: modelDirectory)

        // NaViT (model.visionModel) is unused; set numHiddenLayers=0 to avoid wasted allocation
        let sparseConfig = PaddleOCRVLConfig(
            visionConfig: PaddleOCRVLVisionConfig(
                hiddenSize: config.visionConfig.hiddenSize,
                numHiddenLayers: 0,
                numAttentionHeads: config.visionConfig.numAttentionHeads,
                numChannels: config.visionConfig.numChannels,
                imageSize: config.visionConfig.imageSize,
                patchSize: config.visionConfig.patchSize,
                layerNormEps: config.visionConfig.layerNormEps,
                intermediateSize: config.visionConfig.intermediateSize
            ),
            textConfig: config.textConfig,
            imageTokenIndex: config.imageTokenIndex,
            visionStartTokenId: config.visionStartTokenId,
            visionEndTokenId: config.visionEndTokenId,
            visionTokenId: config.visionTokenId
        )

        let model = PaddleOCRVLModel(config: sparseConfig)
        let projector = MangaMultiModalProjector(config: sparseConfig)
        let visionEncoder = MangaVisionEncoder(
            hiddenSize: config.visionConfig.hiddenSize,
            numHeads: config.visionConfig.numAttentionHeads,
            numLayers: visionNumLayers,
            patchSize: config.visionConfig.patchSize,
            imageSize: config.visionConfig.imageSize,
            intermediateSize: config.visionConfig.intermediateSize,
            layerNormEps: config.visionConfig.layerNormEps
        )

        if let (bits, groupSize) = readQuantizationConfig(from: modelDirectory) {
            let filter: (String, Module) -> Bool = { _, module in
                if let linear = module as? Linear {
                    guard let inFeatures = linear.weight.shape.last else { return false }
                    return inFeatures % groupSize == 0
                } else if module is Embedding {
                    return true
                }
                return false
            }
            MLXNN.quantize(model: model, groupSize: groupSize, bits: bits, filter: filter)
            MLXNN.quantize(model: projector, groupSize: groupSize, bits: bits, filter: filter)
            MLXNN.quantize(model: visionEncoder, groupSize: groupSize, bits: bits, filter: filter)
        }

        try loadWeights(into: model, projector: projector, visionEncoder: visionEncoder, from: modelDirectory)

        let tokenizer = try await AutoTokenizer.from(modelFolder: modelDirectory)
        let tokenizerAdapter = TokenizerAdapter(tokenizer: tokenizer, config: config)
        let imagePreprocessor = ImagePreprocessor(context: CIContext())
        let generator = GeneratorRuntime(
            model: model,
            stopTokens: tokenizerAdapter.stopTokens,
            settings: generationSettings
        )

        return PaddleOCRVLRuntime(
            model: model,
            visionEncoder: visionEncoder,
            projector: projector,
            tokenizerAdapter: tokenizerAdapter,
            imagePreprocessor: imagePreprocessor,
            generator: generator,
            config: config,
            numVisionLayers: visionNumLayers
        )
    }

    private static func loadConfig(from directory: URL) throws -> PaddleOCRVLConfig {
        let data = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return try PaddleOCRVLConfig.load(from: directory)
        }

        let textConfigDict = raw["text_config"] as? [String: Any] ?? [:]
        let visionConfigDict = raw["vision_config"] as? [String: Any] ?? [:]

        let textConfig = PaddleOCRVLTextConfig(
            vocabSize: (textConfigDict["vocab_size"] as? Int) ?? (raw["vocab_size"] as? Int) ?? 48000,
            headDim: (textConfigDict["head_dim"] as? Int) ?? (raw["head_dim"] as? Int),
            hiddenSize: (textConfigDict["hidden_size"] as? Int) ?? (raw["hidden_size"] as? Int) ?? 896,
            intermediateSize: (textConfigDict["intermediate_size"] as? Int) ?? (raw["intermediate_size"] as? Int) ?? 4864,
            numHiddenLayers: (textConfigDict["num_hidden_layers"] as? Int) ?? (raw["num_hidden_layers"] as? Int) ?? 24,
            numAttentionHeads: (textConfigDict["num_attention_heads"] as? Int) ?? (raw["num_attention_heads"] as? Int) ?? 14,
            numKeyValueHeads: (textConfigDict["num_key_value_heads"] as? Int) ?? (raw["num_key_value_heads"] as? Int) ?? 2,
            rmsNormEps: (textConfigDict["rms_norm_eps"] as? Float) ?? (raw["rms_norm_eps"] as? Float) ?? 1e-6,
            ropeTheta: (textConfigDict["rope_theta"] as? Float) ?? (raw["rope_theta"] as? Float) ?? 10_000
        )
        let visionConfig = PaddleOCRVLVisionConfig(
            hiddenSize: (visionConfigDict["hidden_size"] as? Int) ?? 1152,
            numHiddenLayers: (visionConfigDict["num_hidden_layers"] as? Int) ?? 27,
            numAttentionHeads: (visionConfigDict["num_attention_heads"] as? Int) ?? 16,
            numChannels: (visionConfigDict["num_channels"] as? Int) ?? 3,
            imageSize: (visionConfigDict["image_size"] as? Int) ?? 384,
            patchSize: (visionConfigDict["patch_size"] as? Int) ?? 14,
            layerNormEps: (visionConfigDict["layer_norm_eps"] as? Float) ?? 1e-6,
            intermediateSize: (visionConfigDict["intermediate_size"] as? Int) ?? 4304
        )

        return PaddleOCRVLConfig(
            visionConfig: visionConfig,
            textConfig: textConfig,
            imageTokenIndex: (raw["image_token_id"] as? Int) ?? (raw["image_token_index"] as? Int) ?? 100295,
            visionStartTokenId: (raw["vision_start_token_id"] as? Int) ?? 101305,
            visionEndTokenId: (raw["vision_end_token_id"] as? Int) ?? 101306,
            visionTokenId: (raw["image_token_id"] as? Int) ?? 100295
        )
    }

    private static func readVisionNumLayers(from directory: URL) throws -> Int {
        let data = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vc = raw["vision_config"] as? [String: Any],
              let n = vc["num_hidden_layers"] as? Int else { return 27 }
        return n
    }

    private static func readQuantizationConfig(from directory: URL) -> (bits: Int, groupSize: Int)? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("config.json")),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let q = raw["quantization"] as? [String: Any],
              let bits = q["bits"] as? Int,
              let groupSize = q["group_size"] as? Int else { return nil }
        return (bits, groupSize)
    }

    private static func readGenerationSettings(from directory: URL) -> GeneratorRuntime.GenerationSettings {
        let fallback = GeneratorRuntime.GenerationSettings(maxNewTokens: 300, noRepeatNgramSize: 3)
        let url = directory.appendingPathComponent("generation_config.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(PaddleOCRGenerationConfig.self, from: data) else {
            return fallback
        }

        let maxNewTokens = max(1, config.maxLength ?? fallback.maxNewTokens)
        let noRepeatNgramSize = max(0, config.noRepeatNgramSize ?? fallback.noRepeatNgramSize)
        return GeneratorRuntime.GenerationSettings(
            maxNewTokens: maxNewTokens,
            noRepeatNgramSize: noRepeatNgramSize
        )
    }

    private static func loadWeights(
        into model: PaddleOCRVLModel,
        projector: MangaMultiModalProjector,
        visionEncoder: MangaVisionEncoder,
        from directory: URL
    ) throws {
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

        var modelWeights: [String: MLXArray] = [:]
        var projectorWeights: [String: MLXArray] = [:]
        var visionWeights: [String: MLXArray] = [:]

        for (key, value) in all {
            if key.contains("rotary_emb.inv_freq") { continue }

            // 1. Projector weights
            if key.hasPrefix("visual.projector.") {
                let sub = String(key.dropFirst("visual.projector.".count))
                if sub.hasPrefix("pre_norm.") {
                    projectorWeights["preNorm." + sub.dropFirst("pre_norm.".count)] = value
                } else if sub.hasPrefix("linear_1.") {
                    projectorWeights["linear1." + sub.dropFirst("linear_1.".count)] = value
                } else if sub.hasPrefix("linear_2.") {
                    projectorWeights["linear2." + sub.dropFirst("linear_2.".count)] = value
                }
                continue
            }

            var k = key

            // 2. Vision encoder: strip "visual." prefix only — all @ModuleInfo keys are snake_case
            if k.hasPrefix("visual.") {
                visionWeights[String(k.dropFirst("visual.".count))] = value
                continue
            }

            // 3. Language model: strip "language_model." prefix
            if k.hasPrefix("language_model.") {
                k = String(k.dropFirst("language_model.".count))
            }

            modelWeights[k] = value
        }

        try model.update(parameters: ModuleParameters.unflattened(modelWeights), verify: .none)
        try projector.update(parameters: ModuleParameters.unflattened(projectorWeights), verify: .none)
        try visionEncoder.update(parameters: ModuleParameters.unflattened(visionWeights), verify: .none)
    }

    private static func runBlocking<T>(_ op: @escaping () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        Task(priority: .userInitiated) {
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
