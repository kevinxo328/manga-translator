import Foundation
import MLX
import MLXNN
import MLXFast

private func rotateHalfText(_ x: MLXArray) -> MLXArray {
    let half = x.dim(-1) / 2
    let x1 = x[.ellipsis, ..<half]
    let x2 = x[.ellipsis, half...]
    return concatenated([-x2, x1], axis: -1)
}

// Compute cos/sin embeddings for 3 axes (t, h, w) using the same invFreq.
// positionIds: (3, seqLen) — axis 0=t, 1=h, 2=w
// Returns cosAll, sinAll each shaped (3, seqLen, headDim)
private func multimodalRotaryEmbedding(
    positionIds: MLXArray,
    invFreq: MLXArray
) -> (cosAll: MLXArray, sinAll: MLXArray) {
    let posFloat = positionIds.asType(.float32)  // (3, seqLen)
    // outer product per axis: (3, seqLen, halfDim) via broadcasting
    let freqs = posFloat.expandedDimensions(axis: -1) * invFreq  // (3,seqLen,1) * (halfDim,)
    let emb = concatenated([freqs, freqs], axis: -1)  // (3, seqLen, headDim)
    return (MLX.cos(emb), MLX.sin(emb))
}

// Reassemble per-section cos/sin using mrope_section axes assignment.
// cosAll, sinAll: (3, seqLen, headDim) — axis 0=t, 1=h, 2=w
// mropeSection: e.g. [16, 24, 24] → doubled=[16,24,24,16,24,24] → splitPoints=[16,40,64,80,104]
// Returns assembled cos, sin each shaped (seqLen, headDim)
private func assembleMrope(
    cosAll: MLXArray,
    sinAll: MLXArray,
    mropeSection: [Int]
) -> (cos: MLXArray, sin: MLXArray) {
    let headDim = cosAll.dim(2)
    let doubled = mropeSection + mropeSection
    var splitPoints: [Int] = []
    var cumsum = 0
    for v in doubled.dropLast() {
        cumsum += v
        splitPoints.append(cumsum)
    }
    let boundaries = splitPoints + [headDim]

    var cosSlices: [MLXArray] = []
    var sinSlices: [MLXArray] = []
    var start = 0
    for (i, end) in boundaries.enumerated() {
        let axis = i % 3
        let cosAxis = cosAll[axis]  // (seqLen, headDim)
        let sinAxis = sinAll[axis]
        cosSlices.append(cosAxis[.ellipsis, start..<end])
        sinSlices.append(sinAxis[.ellipsis, start..<end])
        start = end
    }
    return (concatenated(cosSlices, axis: -1), concatenated(sinSlices, axis: -1))
}

public class RoPE: Module {
    let dimensions: Int
    let traditional: Bool
    let base: Float
    let scale: Float
    let invFreq: MLXArray

    public init(dimensions: Int, traditional: Bool = false, base: Float = 10_000, scale: Float = 1.0) {
        self.dimensions = dimensions
        self.traditional = traditional
        self.base = base
        self.scale = scale
        
        let freqs = MLXArray(stride(from: 0, to: dimensions, by: 2).map { Float($0) })
        self.invFreq = 1.0 / MLX.pow(base, freqs / Float(dimensions))
        super.init()
    }

    public func callAsFunction(_ x: MLXArray, offset: Int = 0) -> MLXArray {
        let seqLen = x.dim(2)
        let positionIds = MLXArray((offset..<(offset + seqLen)).map { Float($0) })
        
        let freqs = matmul(
            positionIds.expandedDimensions(axis: 1),
            invFreq.expandedDimensions(axis: 0)
        )
        
        let emb = concatenated([freqs, freqs], axis: -1)
        
        let cos = MLX.cos(emb).expandedDimensions(axis: 0).expandedDimensions(axis: 0)
        let sin = MLX.sin(emb).expandedDimensions(axis: 0).expandedDimensions(axis: 0)
        
        let xFloat = x.asType(.float32)
        let out = (xFloat * cos) + (rotateHalfText(xFloat) * sin)
        return out.asType(x.dtype)
    }
}

public class KVCache {
    var keys: MLXArray?
    var values: MLXArray?
    public var offset: Int = 0

    public init() {}

    public func update(keys: MLXArray, values: MLXArray) -> (MLXArray, MLXArray) {
        if let existingKeys = self.keys, let existingValues = self.values {
            self.keys = concatenated([existingKeys, keys], axis: 2)
            self.values = concatenated([existingValues, values], axis: 2)
        } else {
            self.keys = keys
            self.values = values
        }
        self.offset += keys.dim(2)
        return (self.keys!, self.values!)
    }

    public func reset() {
        keys = nil
        values = nil
        offset = 0
    }
}

public class ERNIEAttention: Module {
    let config: PaddleOCRVLTextConfig
    let scale: Float
    let numHeads: Int
    let numKVHeads: Int
    let headDim: Int

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    let rope: RoPE

    public init(config: PaddleOCRVLTextConfig) {
        self.config = config
        self.numHeads = config.numAttentionHeads
        self.numKVHeads = config.numKeyValueHeads
        self.headDim = config.headDim ?? (config.hiddenSize / config.numAttentionHeads)
        self.scale = pow(Float(headDim), -0.5)

        let dim = config.hiddenSize

        self._qProj.wrappedValue = Linear(dim, numHeads * headDim, bias: false)
        self._kProj.wrappedValue = Linear(dim, numKVHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(dim, numKVHeads * headDim, bias: false)
        self._oProj.wrappedValue = Linear(numHeads * headDim, dim, bias: false)

        self.rope = RoPE(
            dimensions: headDim,
            traditional: false,
            base: config.ropeTheta,
            scale: 1.0
        )

        super.init()
    }

    public func callAsFunction(
        _ x: MLXArray,
        mask: MLXArray?,
        cache: KVCache?,
        positionEmbeds: (cos: MLXArray, sin: MLXArray)? = nil
    ) -> MLXArray {
        debug(x, mask: mask, cache: cache, positionEmbeds: positionEmbeds).output
    }

    public func debug(
        _ x: MLXArray,
        mask: MLXArray?,
        cache: KVCache?,
        positionEmbeds: (cos: MLXArray, sin: MLXArray)? = nil
    ) -> (
        output: MLXArray,
        rawQueries: MLXArray,
        rawKeys: MLXArray,
        rawValues: MLXArray,
        queries: MLXArray,
        keys: MLXArray,
        values: MLXArray,
        weights: MLXArray
    ) {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))

        var queries = qProj(x)
        var keys = kProj(x)
        var values = vProj(x)

        queries = queries.reshaped(B, L, numHeads, -1).transposed(0, 2, 1, 3)
        keys = keys.reshaped(B, L, numKVHeads, -1).transposed(0, 2, 1, 3)
        values = values.reshaped(B, L, numKVHeads, -1).transposed(0, 2, 1, 3)
        let rawQueries = queries
        let rawKeys = keys
        let rawValues = values

        if let (cos, sin) = positionEmbeds {
            // Multimodal 3D RoPE: cos/sin already assembled per mrope_section
            // cos, sin: (seqLen, headDim) → expand to (1, 1, seqLen, headDim)
            let cosExp = cos.expandedDimensions(axis: 0).expandedDimensions(axis: 0)
            let sinExp = sin.expandedDimensions(axis: 0).expandedDimensions(axis: 0)
            let qF = queries.asType(.float32)
            let kF = keys.asType(.float32)
            queries = (qF * cosExp + rotateHalfText(qF) * sinExp).asType(queries.dtype)
            keys = (kF * cosExp + rotateHalfText(kF) * sinExp).asType(keys.dtype)
        } else {
            let offset = cache?.offset ?? 0
            queries = rope(queries, offset: offset)
            keys = rope(keys, offset: offset)
        }

        if let cache = cache {
            (keys, values) = cache.update(keys: keys, values: values)
        }

        if numKVHeads < numHeads {
            let repeats = numHeads / numKVHeads
            keys = expandedKVHeads(keys, repeats: repeats)
            values = expandedKVHeads(values, repeats: repeats)
        }

        var scores = matmul(queries, keys.transposed(0, 1, 3, 2)) * scale

        if let mask = mask {
            scores = scores + mask
        }

        let weights = softmax(scores, axis: -1)
        var output = matmul(weights, values)

        output = output.transposed(0, 2, 1, 3).reshaped(B, L, -1)

        return (oProj(output), rawQueries, rawKeys, rawValues, queries, keys, values, weights)
    }

    private func expandedKVHeads(_ x: MLXArray, repeats: Int) -> MLXArray {
        let (B, nKVHeads, L, D) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let expanded = x.expandedDimensions(axis: 2)
        let repeated = MLX.repeated(expanded, count: repeats, axis: 2)
        return repeated.reshaped(B, nKVHeads * repeats, L, D)
    }
}

public class ERNIEMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    public init(config: PaddleOCRVLTextConfig) {
        let hiddenSize = config.hiddenSize
        let intermediateSize = config.intermediateSize

        self._gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: false)

        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

public class RMSNorm: Module {
    let eps: Float
    var weight: MLXArray

    public init(dimensions: Int, eps: Float = 1e-6) {
        self.eps = eps
        self.weight = MLXArray.ones([dimensions])
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x, weight: weight, eps: eps)
    }
}

public class ERNIEDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: ERNIEAttention
    @ModuleInfo(key: "mlp") var mlp: ERNIEMLP
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    public init(config: PaddleOCRVLTextConfig) {
        self._selfAttn.wrappedValue = ERNIEAttention(config: config)
        self._mlp.wrappedValue = ERNIEMLP(config: config)
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)

        super.init()
    }

    public func callAsFunction(
        _ x: MLXArray,
        mask: MLXArray?,
        cache: KVCache?,
        positionEmbeds: (cos: MLXArray, sin: MLXArray)? = nil
    ) -> MLXArray {
        debug(x, mask: mask, cache: cache, positionEmbeds: positionEmbeds).output
    }

    public func debug(
        _ x: MLXArray,
        mask: MLXArray?,
        cache: KVCache?,
        positionEmbeds: (cos: MLXArray, sin: MLXArray)? = nil
    ) -> (
        output: MLXArray,
        inputNorm: MLXArray,
        attentionOutput: MLXArray,
        attentionRawQueries: MLXArray,
        attentionRawKeys: MLXArray,
        attentionRawValues: MLXArray,
        attentionQueries: MLXArray,
        attentionKeys: MLXArray,
        attentionValues: MLXArray,
        attentionWeights: MLXArray,
        residualAfterAttention: MLXArray,
        postAttentionNorm: MLXArray,
        mlpOutput: MLXArray
    ) {
        let inputNorm = inputLayerNorm(x)
        let attentionDebug = selfAttn.debug(inputNorm, mask: mask, cache: cache, positionEmbeds: positionEmbeds)
        var h = attentionDebug.output
        h = x + h
        let postAttentionNorm = postAttentionLayerNorm(h)
        let mlpOutput = mlp(postAttentionNorm)
        return (
            h + mlpOutput,
            inputNorm,
            attentionDebug.output,
            attentionDebug.rawQueries,
            attentionDebug.rawKeys,
            attentionDebug.rawValues,
            attentionDebug.queries,
            attentionDebug.keys,
            attentionDebug.values,
            attentionDebug.weights,
            h,
            postAttentionNorm,
            mlpOutput
        )
    }
}

public class ERNIEModelInner: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [ERNIEDecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    let config: PaddleOCRVLTextConfig

    public init(config: PaddleOCRVLTextConfig) {
        self.config = config

        self._embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabSize, dimensions: config.hiddenSize)

        var decoderLayers: [ERNIEDecoderLayer] = []
        for _ in 0..<config.numHiddenLayers {
            decoderLayers.append(ERNIEDecoderLayer(config: config))
        }
        self._layers.wrappedValue = decoderLayers

        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)

        super.init()
    }

    public func callAsFunction(
        _ inputIds: MLXArray,
        cache: [KVCache]?
    ) -> MLXArray {
        let h = embedTokens(inputIds)
        return forward(h, cache: cache)
    }

    public func forward(
        _ inputsEmbeds: MLXArray,
        positionIds: MLXArray? = nil,
        cache: [KVCache]?
    ) -> MLXArray {
        var h = inputsEmbeds
        let mask = createAttentionMask(h: h, cache: cache)

        let positionEmbeds = makePositionEmbeds(positionIds: positionIds)

        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i], positionEmbeds: positionEmbeds)
        }

        return norm(h)
    }

    // Compute assembled (cos, sin) from 3D position IDs, or nil for sequential RoPE fallback.
    private func makePositionEmbeds(
        positionIds: MLXArray?
    ) -> (cos: MLXArray, sin: MLXArray)? {
        guard let posIds = positionIds,
              let mropeSec = config.mropeSection else { return nil }
        let headDim = config.headDim ?? (config.hiddenSize / config.numAttentionHeads)
        let freqs = MLXArray(stride(from: 0, to: headDim, by: 2).map { Float($0) })
        let invFreq = 1.0 / MLX.pow(MLXArray(config.ropeTheta), freqs / Float(headDim))
        let (cosAll, sinAll) = multimodalRotaryEmbedding(positionIds: posIds, invFreq: invFreq)
        return assembleMrope(cosAll: cosAll, sinAll: sinAll, mropeSection: mropeSec)
    }

    public func forwardDebug(
        _ inputsEmbeds: MLXArray,
        positionIds: MLXArray? = nil,
        cache: [KVCache]?
    ) -> (finalHidden: MLXArray, layerOutputs: [MLXArray]) {
        var h = inputsEmbeds
        let mask = createAttentionMask(h: h, cache: cache)
        var layerOutputs: [MLXArray] = []

        let positionEmbeds = makePositionEmbeds(positionIds: positionIds)

        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i], positionEmbeds: positionEmbeds)
            layerOutputs.append(h)
        }

        return (norm(h), layerOutputs)
    }

    public func forwardFirstLayerDebug(
        _ inputsEmbeds: MLXArray,
        positionIds: MLXArray? = nil,
        cache: [KVCache]?
    ) -> (
        finalHidden: MLXArray,
        firstLayerInputNorm: MLXArray,
        firstLayerAttentionOutput: MLXArray,
        firstLayerAttentionRawQueries: MLXArray,
        firstLayerAttentionRawKeys: MLXArray,
        firstLayerAttentionRawValues: MLXArray,
        firstLayerAttentionQueries: MLXArray,
        firstLayerAttentionKeys: MLXArray,
        firstLayerAttentionValues: MLXArray,
        firstLayerAttentionWeights: MLXArray,
        firstLayerResidualAfterAttention: MLXArray,
        firstLayerPostAttentionNorm: MLXArray,
        firstLayerMLPOutput: MLXArray,
        firstLayerOutput: MLXArray
    ) {
        var h = inputsEmbeds
        let mask = createAttentionMask(h: h, cache: cache)
        let positionEmbeds = makePositionEmbeds(positionIds: positionIds)
        let firstLayerDebug = layers[0].debug(h, mask: mask, cache: cache?[0], positionEmbeds: positionEmbeds)
        h = firstLayerDebug.output

        for (i, layer) in layers.enumerated() where i > 0 {
            h = layer(h, mask: mask, cache: cache?[i], positionEmbeds: positionEmbeds)
        }

        return (
            norm(h),
            firstLayerDebug.inputNorm,
            firstLayerDebug.attentionOutput,
            firstLayerDebug.attentionRawQueries,
            firstLayerDebug.attentionRawKeys,
            firstLayerDebug.attentionRawValues,
            firstLayerDebug.attentionQueries,
            firstLayerDebug.attentionKeys,
            firstLayerDebug.attentionValues,
            firstLayerDebug.attentionWeights,
            firstLayerDebug.residualAfterAttention,
            firstLayerDebug.postAttentionNorm,
            firstLayerDebug.mlpOutput,
            firstLayerDebug.output
        )
    }

    private func createAttentionMask(h: MLXArray, cache: [KVCache]?) -> MLXArray? {
        let n = h.dim(1)
        let offset = cache?.first?.offset ?? 0

        if n == 1 {
            return nil
        }

        var rinds = MLXArray(Int32(0) ..< Int32(offset + n))
        var linds = offset != 0 ? MLXArray(Int32(offset) ..< Int32(offset + n)) : rinds
        linds = linds[0..., .newAxis]
        rinds = rinds[.newAxis]

        let mask = linds .>= rinds
        let additiveMask = MLX.where(mask, MLXArray(Float(0)), MLXArray(Float(-1e9)))

        return additiveMask.reshaped(1, 1, n, offset + n)
    }

    public func getEmbedding(_ inputIds: MLXArray) -> MLXArray {
        embedTokens(inputIds)
    }
}

public class ERNIELanguageModel: Module {
    @ModuleInfo(key: "model") var model: ERNIEModelInner
    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    let config: PaddleOCRVLTextConfig
    public let vocabSize: Int

    public init(config: PaddleOCRVLTextConfig) {
        self.config = config
        self.vocabSize = config.vocabSize

        self._model.wrappedValue = ERNIEModelInner(config: config)

        if !config.tieWordEmbeddings {
            self._lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabSize, bias: false)
        }

        super.init()
    }

    public func callAsFunction(
        _ inputIds: MLXArray,
        cache: [KVCache]?
    ) -> MLXArray {
        var out = model(inputIds, cache: cache)
        out = computeLogits(out)
        return out
    }

    public func forward(
        inputsEmbeds: MLXArray,
        positionIds: MLXArray? = nil,
        cache: [KVCache]?
    ) -> MLXArray {
        var out = model.forward(inputsEmbeds, positionIds: positionIds, cache: cache)
        out = computeLogits(out)
        return out
    }

    private func computeLogits(_ hiddenStates: MLXArray) -> MLXArray {
        if let lmHead = lmHead {
            return lmHead(hiddenStates)
        } else {
            return model.embedTokens.asLinear(hiddenStates)
        }
    }

    public func getInputEmbeddings(_ inputIds: MLXArray) -> MLXArray {
        model.getEmbedding(inputIds)
    }

    public func newCache() -> [KVCache] {
        (0..<config.numHiddenLayers).map { _ in KVCache() }
    }
}
