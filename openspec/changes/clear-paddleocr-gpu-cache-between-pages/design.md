## Context

The high-accuracy PaddleOCR path runs PaddleOCR-VL through MLX on Apple Silicon. The app already keeps the PaddleOCR recognizer/model instance cached in `OCRRouter` so repeated page processing avoids model reload cost. Separately, MLX maintains a GPU buffer cache that can remain resident after inference.

A targeted diagnostic run on the current workload showed:

- no-clear page-boundary median: 96.1s for 9 inferences
- clear-at-page-boundary median: 95.3s for 9 inferences
- no-clear retained approximately 12.5GB `GPU.cacheMemory` after the round
- clear-at-page-boundary retained 0MB `GPU.cacheMemory` after the round

This change treats page boundaries as the cleanup point for MLX GPU buffer cache while preserving the existing model/recognizer instance cache.

## Goals / Non-Goals

**Goals:**

- Clear MLX GPU buffer cache after each production PaddleOCR page processing attempt.
- Ensure cleanup runs after both successful and failed PaddleOCR page processing.
- Keep the cleanup policy testable without loading MLX models or running inference.
- Preserve existing strict PaddleOCR error behavior and no-fallback semantics.

**Non-Goals:**

- Do not disable or change autoregressive KV cache inside a single PaddleOCR generation.
- Do not unload the PaddleOCR model after every page.
- Do not change translation cache, cache keys, model download lifecycle, or model file layout.
- Do not solve single-inference latency; this change only reduces retained GPU cache pressure between pages.

## Decisions

### D1: Clear MLX GPU buffer cache at the PaddleOCR page boundary

`OCRRouter.processWithPaddleOCR(image:)` is the production page-level boundary that creates/reuses the PaddleOCR recognizer and delegates detection plus per-region recognition to `MangaOCRService`. Placing cleanup there ensures the app clears after a page attempt, not after each crop.

**Alternative considered:** Clear after every crop/inference inside `PaddleOCRVLRecognizer` or `DefaultPaddleOCREngine`. Rejected because it would be lower-level, more invasive, and could add overhead inside the tight generation loop.

### D2: Use a small injected cache-management helper

Introduce a minimal abstraction around MLX GPU cache cleanup so `OCRRouterTests` can verify the policy without importing MLX or loading PaddleOCR. The production helper calls `GPU.clearCache()` on Apple Silicon where MLX is available; other builds use a no-op path.

**Alternative considered:** Call `GPU.clearCache()` directly from `OCRRouter`. Rejected because it makes success/failure cleanup harder to unit-test and spreads architecture-specific MLX imports into routing code.

### D3: Use `defer` so failure paths clean up too

The cleanup should run once per PaddleOCR page attempt whether recognition succeeds, throws a `PaddleOCRError`, or throws an unexpected error. A `defer` in the PaddleOCR path keeps this policy local and hard to bypass.

**Alternative considered:** Call cleanup only after successful recognition. Rejected because a failed page can still leave substantial MLX buffer cache resident.

### D4: Keep model instance cache unchanged

The benchmark only supports clearing MLX GPU buffer cache at page boundaries. It does not justify unloading `cachedPaddleOCR` or clearing the language-model KV cache behavior. The existing recognizer cache should remain in place to avoid repeated model load cost.

**Alternative considered:** Reset/unload the PaddleOCR recognizer after each page. Rejected because it changes lifecycle semantics and likely reintroduces expensive model load overhead.

## Risks / Trade-offs

- **Risk: `GPU.clearCache()` is unavailable or differs across architectures** -> Mitigation: hide MLX-specific calls behind conditional compilation and provide a no-op implementation where unavailable.
- **Risk: cleanup logging or memory metric collection becomes noisy** -> Mitigation: keep logging minimal and avoid making memory metrics required for correctness.
- **Risk: benchmark result is workload-specific** -> Mitigation: scope the requirement to page-boundary MLX buffer cleanup, not a broad claim that all PaddleOCR caching is unnecessary.
- **Risk: cleanup placement misses non-router diagnostic paths** -> Mitigation: this change targets production page processing; diagnostic tests and direct engine experiments may continue to manage cache explicitly.

## Migration Plan

No data migration is required. The change can be rolled back by removing the injected cache cleanup call and helper while leaving PaddleOCR model files and user preferences untouched.

## Open Questions

None.
