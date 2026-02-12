# <img src="MangaTranslator/Assets.xcassets/AppIcon.appiconset/Gemini_Generated_Image_ok7apqok7apqok7a 8.png" width="48" height="48" valign="middle"> MangaTranslator

![GitHub Release](https://img.shields.io/github/v/release/kevinxo328/manga-translator)

A native macOS application that automatically detects, recognizes, and translates text in manga pages. It combines on-device ML models for Japanese OCR with multiple translation engine backends to deliver a seamless reading experience.

## Core Features

- **Manga-Optimized OCR** — Japanese uses bundled ONNX models (Manga-OCR encoder/decoder + YOLOv5-based comic text detector) with Apple Vision as a fallback. English and Traditional Chinese use Apple Vision directly, so the app can OCR manga in all three supported languages.
- **Multiple Translation Engines** — Supports Claude (Anthropic), OpenAI-compatible APIs, DeepL, and Google Translate. The OpenAI-compatible backend supports custom base URLs (for local LLMs, Azure OpenAI, etc.) and free-text model selection.
- **Batch Processing** — Load entire folders or CBZ/ZIP archives and translate all pages concurrently (up to 3 pages in parallel).
- **Interactive Viewer** — Displays detected speech bubbles as overlays on the original image. Click or use keyboard arrows to navigate between bubbles and pages.
- **Translation Caching** — SHA256-based content-addressable cache (SQLite) avoids redundant API calls when revisiting pages.
- **Secure Key Storage** — API keys are stored in the macOS Keychain, not in plaintext.

## Supported Languages

| Source              | OCR Method                            | Target                        |
| ------------------- | ------------------------------------- | ----------------------------- |
| Japanese            | Manga-OCR (ONNX) with Vision fallback | English, Traditional Chinese  |
| English             | Apple Vision                          | Japanese, Traditional Chinese |
| Traditional Chinese | Apple Vision                          | Japanese, English             |

## Installation

1. Download the latest DMG from the [Releases](https://github.com/kevinxo328/manga-translator/releases) page.
2. Open the DMG and drag **MangaTranslator** to the Applications folder.
3. On first launch, macOS will block the app because it is not signed with an Apple Developer certificate. To open it:
   - Go to **System Settings > Privacy & Security**.
   - Scroll down to the Security section and click **Open Anyway** next to the MangaTranslator message.
   - Click **Open** in the confirmation dialog.

## Getting Started

### Prerequisites

- macOS Monterey or later
- Xcode 14+ with Swift 5.0

### Build & Run

```bash
# Open in Xcode
open MangaTranslator.xcodeproj

# Or build from the command line
xcodebuild -project MangaTranslator.xcodeproj \
    -scheme MangaTranslator \
    -configuration Debug \
    build
```

### Configuration

1. Launch the app and open **Settings** (`Cmd + ,`).
2. In the **API Keys** tab, enter credentials for your preferred translation engine(s).
3. In the **Preferences** tab, select the source/target language pair and default engine.

## Project Structure

```
MangaTranslator/
├── MangaTranslatorApp.swift          # App entry point
├── Models/
│   └── Models.swift                  # Core data types (Language, TranslationEngine, BubbleCluster, etc.)
├── ViewModels/
│   └── TranslationViewModel.swift    # Central state management and orchestration
├── Views/
│   ├── ContentView.swift             # Main split-view layout
│   ├── ImageViewer.swift             # Image display with bubble overlays
│   ├── TranslationSidebar.swift      # Scrollable translation card list
│   └── SettingsView.swift            # API keys, preferences, and about tabs
├── Services/
│   ├── OCRRouter.swift               # OCR pipeline orchestrator
│   ├── MangaOCRService.swift         # Manga-OCR ONNX inference
│   ├── ComicTextDetectorService.swift# YOLOv5 text region detection
│   ├── BubbleDetector.swift          # Clusters text observations into bubbles
│   ├── ReadingOrderSorter.swift      # Right-to-left, top-to-bottom ordering
│   ├── Claude/OpenAI/DeepL/Google TranslationService.swift
│   ├── CacheService.swift            # SQLite translation cache
│   ├── KeychainService.swift         # Secure API key storage
│   ├── FileInputService.swift        # Image/folder/archive loading
│   └── PreferencesService.swift      # UserDefaults wrapper
└── Resources/Models/                 # Bundled ONNX models and tokenizer files
```

## Architecture Overview

```
Image Input ─► ComicTextDetector (YOLO) ─► BubbleDetector ─► ReadingOrderSorter
                                                │
                                    MangaOCR / Vision OCR
                                                │
                                    TranslationService (Claude / OpenAI / DeepL / Google)
                                                │
                                         CacheService (SQLite)
                                                │
                                    ImageViewer + TranslationSidebar
```

The `TranslationViewModel` coordinates this pipeline: it receives file input, drives each page through detection → OCR → translation, caches results, and publishes state changes to the SwiftUI views.

## Release

Pushing a version tag (e.g., `v1.0.0`) to the `main` branch triggers the GitHub Actions workflow, which builds the app, packages it as a DMG, and creates a GitHub Release automatically.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Development Notes

- **Language convention** — All code, comments, and UI strings are in English.
- **App Sandbox** — The app runs in a sandbox with network-client and user-selected read-only file access entitlements. Any new file access patterns require entitlement updates.
- **ONNX models** — The bundled models (`encoder_model.onnx`, `decoder_model.onnx`, `comic-text-detector.onnx`) are loaded lazily on first OCR use. They are large binary files tracked in the repository under `Resources/Models/`.
- **API key handling** — Never log or persist API keys outside of Keychain. The `KeychainService` is the single source of truth.
- **Concurrency** — Batch translation uses Swift concurrency (`async/await` with `TaskGroup`), capped at 3 concurrent pages to avoid API rate limits.
- **Cache invalidation** — The cache is keyed by image content hash (SHA256), so re-translating the same image with a different engine or language will create a separate cache entry.
