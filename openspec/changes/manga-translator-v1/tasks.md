## 1. Project Setup

- [x] 1.1 Create Xcode project (SwiftUI App, macOS 13+, sandboxed) with bundle ID com.chunweiliu.MangaTranslator
- [x] 1.2 Configure entitlements: App Sandbox, Network (outgoing), File Access (user-selected)
- [x] 1.3 Remove Python project files (main.py, pyproject.toml, .python-version)
- [x] 1.4 Set up basic app structure: App entry point, main window, and placeholder views

## 2. Data Models

- [x] 2.1 Define core data models: Language enum (ja, en, zhHant), TranslationEngine enum, TextObservation struct, BubbleCluster struct, TranslatedBubble struct
- [x] 2.2 Define PageState enum (pending, processing, translated, error) for batch processing
- [x] 2.3 Define TranslationService protocol with translate(bubbles:from:to:) async throws -> [TranslatedBubble]

## 3. OCR Pipeline

- [x] 3.1 Implement VisionOCRService: run VNRecognizeTextRequest on a CGImage, return [TextObservation]
- [x] 3.2 Implement coordinate normalization: Vision bottom-left normalized → image top-left pixel coordinates
- [x] 3.3 Configure recognition languages (ja, en, zh-Hant) and accuracy level (.accurate)

## 4. Bubble Detection

- [x] 4.1 Implement BubbleDetector: agglomerative clustering of TextObservations by spatial proximity
- [x] 4.2 Implement adaptive distance threshold (2x median character height)
- [x] 4.3 Implement bubble text concatenation (top-to-bottom ordering within cluster)
- [x] 4.4 Compute union bounding rect for each bubble cluster

## 5. Reading Order

- [x] 5.1 Implement spatial reading order: partition bubbles into rows by Y-overlap, sort rows top-to-bottom, sort within rows right-to-left
- [x] 5.2 Integrate LLM order correction into LLM translation prompt (include bubble positions, request reordering)

## 6. Translation Backends

- [x] 6.1 Implement DeepLTranslationService: REST API calls, per-bubble translation, API key from Keychain
- [x] 6.2 Implement GoogleTranslationService: Cloud Translation API, per-bubble translation
- [x] 6.3 Implement OpenAITranslationService: whole-page prompt with bubble positions, JSON response parsing
- [x] 6.4 Implement ClaudeTranslationService: whole-page prompt with bubble positions, JSON response parsing
- [x] 6.5 Implement LLM JSON response parsing with retry logic (up to 2 retries, fallback to line-by-line)
- [x] 6.6 Design LLM system prompt for manga translation (include reading order correction instructions)

## 7. Translation Cache

- [x] 7.1 Implement SQLite database setup: create cache.sqlite in app container, create tables (translation_cache, history)
- [x] 7.2 Implement image SHA256 hashing
- [x] 7.3 Implement cache lookup: query by (image_hash, source_lang, target_lang, engine)
- [x] 7.4 Implement cache write: store bubbles_json with positions, original text, translations, reading order
- [x] 7.5 Integrate cache into translation pipeline: check cache before OCR, write after translation

## 8. Settings & API Key Management

- [x] 8.1 Implement KeychainService: store/retrieve/delete API keys using Security framework
- [x] 8.2 Implement SettingsView: API key fields for DeepL, Google, OpenAI, Anthropic
- [x] 8.3 Implement UserDefaults storage for preferences (default language pair, default engine)
- [x] 8.4 Implement API key validation check before translation with alert to open settings

## 9. Image Viewer UI

- [x] 9.1 Implement main split view layout: HSplitView with image viewer (left) and sidebar (right)
- [x] 9.2 Implement image display with zoom/pan support
- [x] 9.3 Implement bubble overlay: numbered indicators at each bubble position, coordinate conversion from image space to view space
- [x] 9.4 Implement hover popover: show translated text when hovering over bubble region
- [x] 9.5 Implement sidebar translation list: numbered entries with original text and translation
- [x] 9.6 Implement sidebar-to-image highlighting: click sidebar entry → highlight corresponding bubble

## 10. File Input

- [x] 10.1 Implement file open via NSOpenPanel / .fileImporter (Cmd+O) for images, folders, and archives
- [x] 10.2 Implement drag-and-drop onto app window (.onDrop)
- [x] 10.3 Implement paste from clipboard (Cmd+V)
- [x] 10.4 Implement .zip/.cbz extraction to temporary sandbox directory
- [x] 10.5 Implement folder scanning: find image files, sort by filename

## 11. Batch Processing

- [x] 11.1 Implement BatchTranslationViewModel: manage array of page states, coordinate background translation
- [x] 11.2 Implement progressive translation with TaskGroup (max 3 concurrent)
- [x] 11.3 Implement page navigation UI: previous/next buttons, page indicator, keyboard shortcuts (arrow keys)
- [x] 11.4 Implement batch progress display ("12/30 pages translated")

## 12. Integration & Polish

- [x] 12.1 Wire up full pipeline: image load → OCR → bubble detect → order → translate → display
- [x] 12.2 Implement language/engine selector in toolbar with re-translation on change
- [x] 12.3 Add loading states and error handling throughout the UI
- [x] 12.4 Add app icon and menu bar setup (File menu, Settings shortcut Cmd+,)
