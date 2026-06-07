# <img src="MangaTranslator/Assets.xcassets/AppIcon.appiconset/Gemini_Generated_Image_ok7apqok7apqok7a 8.png" width="48" height="48" valign="middle"> MangaTranslator

![GitHub Release](https://img.shields.io/github/v/release/kevinxo328/manga-translator)

A native macOS application that automatically detects, recognizes, and translates text in manga pages. It combines on-device ML models for Japanese OCR with multiple translation engine backends to deliver a seamless reading experience.

## Core Features

- **Manga-Optimized OCR** — Powered by the **2025 fine-tuned Manga-OCR** (ONNX). It is specifically optimized for modern manga, providing high accuracy for artistic fonts, vertical text, sound effects (SFX), and furigana. On Apple Silicon with **16GB RAM or more**, an optional downloadable PaddleOCR-VL path provides higher-accuracy recognition.
- **Multiple Translation Engines** — Supports OpenAI-compatible APIs, DeepL, Google Translate, and GitHub Copilot. The OpenAI-compatible backend supports custom base URLs (for local LLMs, Azure OpenAI, etc.) and free-text model selection. The GitHub Copilot backend reads the OAuth token from the local keychain (installed by the Copilot CLI) — no API key entry required.
- **Glossary System** — Create named glossaries to pin character names, technique names, and place names to your preferred translations. Glossary terms are injected into every translation request across all supported engines. The OpenAI-compatible backend auto-detects new proper nouns during translation and adds them to the active glossary automatically.
- **Cross-page Context** — When using the OpenAI-compatible engine, a rolling window of the last 3 translated pages is included in each prompt, helping the model maintain narrative continuity and consistent character references across pages.
- **Batch Processing** — Load entire folders or CBZ/ZIP archives and translate all pages concurrently (up to 3 pages in parallel).
- **Interactive Viewer** — Displays detected speech bubbles as overlays on the original image. Click or use keyboard arrows to navigate between bubbles and pages.
- **Translation Caching** — SHA256-based content-addressable cache (SQLite) avoids redundant API calls when revisiting pages.
- **Secure Key Storage** — API keys are stored in the macOS Keychain, not in plaintext.

## Supported Languages

| Source            | OCR Method                              |
| ----------------- | --------------------------------------- |
| English, Japanese | Manga-OCR (ONNX), optional PaddleOCR-VL |

Target languages:

- English
- French
- German
- Indonesian
- Japanese
- Korean
- Portuguese (Brazil)
- Simplified Chinese
- Spanish
- Traditional Chinese
- Vietnamese

## Installation

1. Download the latest DMG from the [Releases](https://github.com/kevinxo328/manga-translator/releases) page.
2. Open the DMG and drag **MangaTranslator** to the Applications folder.
3. On first launch, macOS will block the app because it is not signed with an Apple Developer certificate. To open it:
   - Go to **System Settings > Privacy & Security**.
   - Scroll down to the Security section and click **Open Anyway** next to the MangaTranslator message.
   - Click **Open** in the confirmation dialog.
   - **Alternatively**, you can run the following command in Terminal to bypass this:
     ```bash
     xattr -cr /Applications/MangaTranslator.app
     ```

## Getting Started

### Optional PaddleOCR-VL Model

The Apple Silicon PaddleOCR-VL path uses the app-ready MLX model published at
[kevinxo328/paddleocr-vl-manga-mlx](https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx).
That model is converted with the tooling in
[`scripts/convert_model`](scripts/convert_model/README.md) from
[`jzhang533/PaddleOCR-VL-For-Manga`](https://huggingface.co/jzhang533/PaddleOCR-VL-For-Manga)
and packaged for this app's optional high-accuracy OCR workflow.

### Configuration

1. Launch the app and open **Settings** (`Cmd + ,`).
2. In the **API Keys** tab, enter credentials for your preferred translation engine(s).
3. In the **Preferences** tab, select the source/target language pair and default engine.

## Credits & Resources

- **Manga-OCR (2025)** — Based on the original work by [kha-white](https://github.com/kha-white/manga-ocr), updated with [2025 fine-tuned weights](https://huggingface.co/jzhang533/manga-ocr-base-2025) and optimized for ONNX by [l0wgear](https://huggingface.co/l0wgear/manga-ocr-2025-onnx).
- **Text Detection** — Comic text detector based on YOLOv5.
- **PaddleOCR-VL MLX model** — App-ready converted model published at [kevinxo328/paddleocr-vl-manga-mlx](https://huggingface.co/kevinxo328/paddleocr-vl-manga-mlx), produced with [`scripts/convert_model`](scripts/convert_model/README.md) from [jzhang533/PaddleOCR-VL-For-Manga](https://huggingface.co/jzhang533/PaddleOCR-VL-For-Manga), licensed under Apache 2.0. Used as an optional downloadable model for Apple Silicon.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license details.
