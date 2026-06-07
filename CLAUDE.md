## Overview

MangaTranslator is a native macOS app that detects, OCRs, and translates manga speech bubbles.

- **Language**: Swift (`SWIFT_VERSION = 5.0`); codebase adopts Swift 6-style concurrency annotations (`@MainActor`, actor-isolated services).
- **UI framework**: SwiftUI (with AppKit interop where needed — `NSImage`, `NSPasteboard`, etc.).
- **Platform**: macOS only — minimum deployment target **macOS 15 (Sequoia)**.
- **Architecture**: MVVM; `TranslationViewModel` is `@MainActor`.
- **Build system**: Xcode project (`MangaTranslator.xcodeproj`). Root `Package.swift` is only for the `DetectorExportCLI` helper, not the app.
- **ML stack**:
  - **ONNX Runtime** (`OnnxRuntimeBindings`) — bubble detector (`ComicTextDetectorService`) and `MangaOCRRecognizer`.
  - **MLX** (Metal) — PaddleOCR engine in the `MangaTranslatorMLX` target; ships a `default.metallib` that the release pipeline must preserve (see Release).
- **Testing**: XCTest + Swift Testing (`import Testing`), split across three schemes (see Testing).
- **Distribution**: `.dmg` produced by `scripts/build_dmg.sh`; the release workflow signs it for Sparkle appcast updates when version tags are pushed.

## Project Layout

```text
MangaTranslator/
├── MangaTranslatorApp.swift  # App entry point
├── Models/                   # Data structures and core types
├── Services/                 # OCR, translation, persistence, and integration logic
├── ViewModels/               # App state and orchestration
├── Views/                    # SwiftUI interface components
└── Resources/                # Bundled ML models and assets
MangaTranslatorTests/         # Main unit and integration tests
OCRBenchmarkTests/            # OCR benchmark tests, separate scheme
openspec/                     # Technical specifications and change tracking
scripts/                      # Build, conversion, and release automation
Vendor/paddleocr-vl.swift/    # Vendored PaddleOCR-VL Swift dependency
```

## Architecture

```text
Image Input -> ComicTextDetector (YOLO) -> BubbleDetector -> ReadingOrderSorter
                                                   |
                                      MangaOCR / PaddleOCR
                                                   |
                         TranslationService (OpenAI / DeepL / Google / Copilot)
                                                   |
                                      CacheService (SQLite)
                                                   |
                              ImageViewer + TranslationSidebar
```

`TranslationViewModel` coordinates the pipeline. It receives file input, drives each page through detection, OCR, translation, cache lookup/storage, and publishes state changes to SwiftUI views.

## Specifications (OpenSpec)

This repository follows a spec-driven development workflow. All capability and feature specifications are documented under the [openspec/specs](file:///Users/chunweiliu/Repos/manga-translator/openspec/specs) directory.

- **Spec Location**: `openspec/specs/<feature-name>/spec.md` (e.g., [ocr-benchmark spec](file:///Users/chunweiliu/Repos/manga-translator/openspec/specs/ocr-benchmark/spec.md))

## Build & Run

```bash
# Build (Debug)
xcodebuild -project MangaTranslator.xcodeproj \
    -scheme MangaTranslator \
    -configuration Debug \
    build

# Open in Xcode
open MangaTranslator.xcodeproj
```

The `PaddleOCRVL` dependency is vendored at `Vendor/paddleocr-vl.swift` so the text-side rotary parity fix stays versioned in this repository instead of living in SwiftPM or Xcode cache directories.

## Testing

Three separate test schemes serve different purposes — do not conflate them:

```bash
# Main unit/integration suite — run this for all normal development
xcodebuild test -project MangaTranslator.xcodeproj \
    -scheme MangaTranslator \
    -destination 'platform=macOS'

# OCR quality benchmark (requires manga images under examples/)
xcodebuild test -project MangaTranslator.xcodeproj \
    -scheme OCRBenchmark \
    -destination 'platform=macOS'

# PaddleOCR parity diagnostics — only for deep PaddleOCR investigation
xcodebuild test -project MangaTranslator.xcodeproj \
    -scheme PaddleOCRParityDiagnostic \
    -destination 'platform=macOS'
```

To run a single test class or method, append `-only-testing MangaTranslatorTests/<TestClass>/<testMethod>`.

### Test Suite Guidance

- **MangaTranslator**: main unit and integration suite for app logic, view models, services, UI correctness, and general OCR regressions. Run this for normal development and before merging.
- **OCRBenchmark**: production-style benchmark comparing PaddleOCR and MangaOCR on real manga pages. Use it for quality, pairing, and latency evaluation, not fast regression feedback.
- **PaddleOCRParityDiagnostic**: artifact-driven diagnostic suite for PaddleOCR parity investigations. It is intentionally outside the main scheme because it is heavier and needs specific artifacts.

### OCR Benchmark Setup

Place benchmark images under `examples/` at any subdirectory depth. Supported extensions are `.jpg`, `.jpeg`, and `.png`. The scanner skips subdirectories whose names start with `.` or `_`.

Each engine runs as an independent production pipeline. Results are anchored on PaddleOCR and paired against MangaOCR by greedy IoU matching with threshold `>= 0.5`. Reports include paired regions, text, IoU score, unmatched sections, per-engine latency, and image failure counts. The report prints to the Xcode console and is also saved as a test result attachment under `testFullBenchmark`.

### PaddleOCR Parity Diagnostics Setup

Use this suite only for PaddleOCR-specific parity problems. Provide artifacts with one of these mechanisms:

- Set `ENABLE_PADDLEOCR_DIAGNOSTIC_TESTS=1`.
- Set `PADDLEOCR_DETECTOR_JSON_PATH` / `PADDLEOCR_VERIFY_JSON_PATH`.
- Place supported files under `.artifacts/paddleocr/`.

### Platform Constraints

- **App Sandbox** is enabled. Network entitlement is `com.apple.security.network.client`. File access uses the user-selected read-write entitlement. New file access patterns require entitlement changes in `MangaTranslator.entitlements`.
- Minimum deployment target: **macOS 15 (Sequoia)**.
- Swift 6 concurrency — `TranslationViewModel` is `@MainActor`; services that touch `@MainActor` state must be annotated accordingly.

## Development Constraints

- **Language convention**: all code, comments, and UI strings are in English.
- **API keys**: never log or persist API keys outside Keychain. `KeychainService` is the single source of truth.
- **ONNX models**: bundled models (`encoder_model.onnx`, `decoder_model.onnx`, `comic-text-detector.onnx`) are large tracked binaries under `Resources/Models/` and load lazily on first OCR use.
- **Batch concurrency**: batch translation uses Swift concurrency (`async`/`await` with `TaskGroup`) and is capped at 3 concurrent pages to avoid API rate limits.
- **Cache semantics**: cache entries are keyed by image content hash (SHA256) plus translation context such as engine/language, so changing engine or language creates distinct results.
- **Optional PaddleOCR-VL model**: the Apple Silicon high-accuracy path uses the app-ready MLX model at [kevinxo328/paddleocr-vl-manga-mlx](https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx), converted with tooling in `scripts/convert_model` from [jzhang533/PaddleOCR-VL-For-Manga](https://huggingface.co/jzhang533/PaddleOCR-VL-For-Manga).

## Release

Pushing a version tag triggers the GitHub Actions workflow (`release.yml`), which calls `scripts/build_dmg.sh`, signs the DMG for Sparkle updates, generates `appcast.xml`, and creates the GitHub Release.

`default.metallib` is required by the MLX runtime. The app target's Xcode build phase copies `mlx-swift_Cmlx.bundle` into the app resources, and `scripts/build_dmg.sh` verifies the metallib exists before signing and packaging. Do not remove that build phase or the release-time verification.

```bash
git tag v1.x.x
git push origin v1.x.x
```

## `Package.swift`

The root `Package.swift` is **only** for `DetectorExportCLI`, a standalone command-line tool that exports the YOLO detector. It is not the main app build system (that is `MangaTranslator.xcodeproj`).
