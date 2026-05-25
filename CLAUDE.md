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
- **Distribution**: Signed `.dmg` produced by `scripts/build_dmg.sh`, triggered by version tags via GitHub Actions.

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

### Platform Constraints

- **App Sandbox** is enabled. Network entitlement is `com.apple.security.network.client`. File access is user-selected read-only. New file access patterns require entitlement changes in `MangaTranslator.entitlements`.
- Minimum deployment target: **macOS 15 (Sequoia)**.
- Swift 6 concurrency — `TranslationViewModel` is `@MainActor`; services that touch `@MainActor` state must be annotated accordingly.

## Release

Pushing a version tag triggers the GitHub Actions workflow (`release.yml`), which calls `scripts/build_dmg.sh`. That script has a critical recovery step (steps 4a/4b) that copies `default.metallib` from the MLX bundle back into the archive after `xcodebuild archive` drops it — **do not remove or reorder those steps**.

```bash
git tag v1.x.x
git push origin v1.x.x
```

## `Package.swift`

The root `Package.swift` is **only** for `DetectorExportCLI`, a standalone command-line tool that exports the YOLO detector. It is not the main app build system (that is `MangaTranslator.xcodeproj`).
