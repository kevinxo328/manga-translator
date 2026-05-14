## Why

PaddleOCR inference leaves a large MLX GPU buffer cache resident after page processing, which can push the app or desktop into a Not Responding state on real hardware. A targeted diagnostic run showed that clearing MLX GPU cache at page boundaries removes the retained cache without a measurable throughput penalty for the tested workload.

## What Changes

- Clear MLX GPU buffer cache after each PaddleOCR page processing attempt completes.
- Apply the cleanup on both successful and failed PaddleOCR page paths so errors do not leave large transient cache allocations resident.
- Keep the model/recognizer instance cache intact; this change does not unload the PaddleOCR model after each page.
- Keep autoregressive KV cache behavior unchanged; this change only concerns MLX GPU buffer-pool cache.
- Add focused tests for the cleanup policy without running real MLX inference.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `high-accuracy-ocr`: Add a page-boundary MLX GPU cache cleanup requirement for the PaddleOCR high-accuracy OCR path.

## Impact

- Affects `OCRRouter` PaddleOCR page processing and/or a small injected cache-management helper.
- May add a tiny production abstraction around `MLX.GPU.clearCache()` with a no-op implementation where MLX is unavailable.
- Affects `OCRRouterTests` or equivalent unit tests for PaddleOCR success/failure cleanup behavior.
- Does not change public user-facing APIs, cache keys, model files, translation cache behavior, or PaddleOCR text generation semantics.
