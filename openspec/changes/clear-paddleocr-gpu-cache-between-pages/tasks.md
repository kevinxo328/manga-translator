## 1. Tests First

- [ ] 1.1 Add an `OCRRouterTests` case proving the PaddleOCR page path invokes the GPU cache cleanup hook exactly once after successful page processing.
- [ ] 1.2 Add an `OCRRouterTests` case proving the PaddleOCR page path invokes the GPU cache cleanup hook exactly once when PaddleOCR page processing throws.
- [ ] 1.3 Add an `OCRRouterTests` case proving the standard MangaOCR page path does not invoke the PaddleOCR GPU cache cleanup hook.
- [ ] 1.4 Run the targeted `OCRRouterTests` cases and confirm they fail before implementation for the missing cleanup policy.

## 2. Cache Cleanup Abstraction

- [ ] 2.1 Add a minimal GPU cache cleanup protocol/helper that exposes page-boundary PaddleOCR cache cleanup without forcing tests to import MLX.
- [ ] 2.2 Add the production Apple Silicon implementation that calls `MLX.GPU.clearCache()`.
- [ ] 2.3 Add a no-op implementation or conditional fallback for builds where MLX is unavailable.

## 3. Production Wiring

- [ ] 3.1 Inject the GPU cache cleanup helper into `OCRRouter` with a production default.
- [ ] 3.2 Use `defer` in `OCRRouter.processWithPaddleOCR(image:)` so cleanup runs once after success and once after failure.
- [ ] 3.3 Preserve the existing cached PaddleOCR recognizer/model instance behavior and strict no-fallback error semantics.
- [ ] 3.4 Ensure `processWithMangaOCR(image:)` does not invoke the PaddleOCR GPU cache cleanup helper.

## 4. Verification

- [ ] 4.1 Re-run the targeted `OCRRouterTests` cases and confirm they pass.
- [ ] 4.2 Run the broader relevant test suite for OCR routing/high-accuracy OCR behavior.
- [ ] 4.3 Run the minimal PaddleOCR cache diagnostic with one page and one round pair to confirm page-boundary cleanup remains safe and measurable.
- [ ] 4.4 Confirm no heavy PaddleOCR diagnostic marker files are left enabled after verification.
