# OCR diagnostic CI

The pull-request workflow runs only the normal `MangaTranslator` scheme and the repository validator. It deliberately excludes the model-heavy OCR diagnostics.

`OCR Diagnostics` runs every Monday at 03:00 UTC and can also be started from the GitHub Actions **Run workflow** menu. It runs the `OCRBenchmark` scheme only.

- **OCR benchmark** reads manga images from `examples/` (recursively) and writes its report as a test attachment. Add only `.jpg`, `.jpeg`, or `.png` inputs; directories beginning with `.` or `_` are ignored. The current corpus is local-only and ignored by Git, so the hosted workflow has no benchmark evidence until an approved public corpus or artifact source is provided.
- **PaddleOCR parity diagnostics** run locally, not in GitHub Actions. They require the downloaded PaddleOCR model plus detector and verification JSON artifacts. Put inputs under `.artifacts/paddleocr/`, set `PADDLEOCR_DETECTOR_JSON_PATH` and `PADDLEOCR_VERIFY_JSON_PATH`, or enable the diagnostics with `ENABLE_PADDLEOCR_DIAGNOSTIC_TESTS=1`, then run `xcodebuild test -project MangaTranslator.xcodeproj -scheme PaddleOCRParityDiagnostic -destination 'platform=macOS'`.

Both diagnostic schemes are intentionally investigative: they produce benchmark/parity evidence and must not become PR merge blockers. GitHub-hosted parity CI is intentionally absent until a runner can access the model and artifacts without uploading private local data.
