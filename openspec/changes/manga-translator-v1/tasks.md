## 1. Project Setup

- [ ] 1.1 Create Xcode project (SwiftUI App, macOS 13+, sandboxed) with bundle ID com.chunweiliu.MangaTranslator
- [ ] 1.2 Configure entitlements: App Sandbox, Network (outgoing), File Access (user-selected)
- [ ] 1.3 Remove Python project files (main.py, pyproject.toml, .python-version)
- [ ] 1.4 Set up basic app structure: App entry point, main window, and placeholder views

## 2. Data Models

- [ ] 2.1 Define core data models: Language enum (ja, en, zhHant), TranslationEngine enum, TextObservation struct, BubbleCluster struct, TranslatedBubble struct
- [ ] 2.2 Define PageState enum (pending, processing, translated, error) for batch processing
- [ ] 2.3 Define TranslationService protocol with translate(bubbles:from:to:) async throws -> [TranslatedBubble]

## 3. OCR Pipeline

- [ ] 3.1 Implement VisionOCRService: run VNRecognizeTextRequest on a CGImage, return [TextObservation]
- [ ] 3.2 Implement coordinate normalization: Vision bottom-left normalized → image top-left pixel coordinates
- [ ] 3.3 Configure recognition languages (ja, en, zh-Hant) and accuracy level (.accurate)

## 4. Bubble Detection

- [ ] 4.1 Implement BubbleDetector: agglomerative clustering of TextObservations by spatial proximity
- [ ] 4.2 Implement adaptive distance threshold (2x median character height)
- [ ] 4.3 Implement bubble text concatenation (top-to-bottom ordering within cluster)
- [ ] 4.4 Compute union bounding rect for each bubble cluster

## 5. Reading Order

- [ ] 5.1 Implement spatial reading order: partition bubbles into rows by Y-overlap, sort rows top-to-bottom, sort within rows right-to-left
- [ ] 5.2 Integrate LLM order correction into LLM translation prompt (include bubble positions, request reordering)

## 6. Translation Backends

- [ ] 6.1 Implement DeepLTranslationService: REST API calls, per-bubble translation, API key from Keychain
- [ ] 6.2 Implement GoogleTranslationService: Cloud Translation API, per-bubble translation
- [ ] 6.3 Implement OpenAITranslationService: whole-page prompt with bubble positions, JSON response parsing
- [ ] 6.4 Implement ClaudeTranslationService: whole-page prompt with bubble positions, JSON response parsing
- [ ] 6.5 Implement LLM JSON response parsing with retry logic (up to 2 retries, fallback to line-by-line)
- [ ] 6.6 Design LLM system prompt for manga translation (include reading order correction instructions)

## 7. Translation Cache

- [ ] 7.1 Implement SQLite database setup: create cache.sqlite in app container, create tables (translation_cache, history)
- [ ] 7.2 Implement image SHA256 hashing
- [ ] 7.3 Implement cache lookup: query by (image_hash, source_lang, target_lang, engine)
- [ ] 7.4 Implement cache write: store bubbles_json with positions, original text, translations, reading order
- [ ] 7.5 Integrate cache into translation pipeline: check cache before OCR, write after translation

## 8. Settings & API Key Management

- [ ] 8.1 Implement KeychainService: store/retrieve/delete API keys using Security framework
- [ ] 8.2 Implement SettingsView: API key fields for DeepL, Google, OpenAI, Anthropic
- [ ] 8.3 Implement UserDefaults storage for preferences (default language pair, default engine)
- [ ] 8.4 Implement API key validation check before translation with alert to open settings

## 9. Image Viewer UI

- [ ] 9.1 Implement main split view layout: HSplitView with image viewer (left) and sidebar (right)
- [ ] 9.2 Implement image display with zoom/pan support
- [ ] 9.3 Implement bubble overlay: numbered indicators at each bubble position, coordinate conversion from image space to view space
- [ ] 9.4 Implement hover popover: show translated text when hovering over bubble region
- [ ] 9.5 Implement sidebar translation list: numbered entries with original text and translation
- [ ] 9.6 Implement sidebar-to-image highlighting: click sidebar entry → highlight corresponding bubble

## 10. File Input

- [ ] 10.1 Implement file open via NSOpenPanel / .fileImporter (Cmd+O) for images, folders, and archives
- [ ] 10.2 Implement drag-and-drop onto app window (.onDrop)
- [ ] 10.3 Implement paste from clipboard (Cmd+V)
- [ ] 10.4 Implement .zip/.cbz extraction to temporary sandbox directory
- [ ] 10.5 Implement folder scanning: find image files, sort by filename

## 11. Batch Processing

- [ ] 11.1 Implement BatchTranslationViewModel: manage array of page states, coordinate background translation
- [ ] 11.2 Implement progressive translation with TaskGroup (max 3 concurrent)
- [ ] 11.3 Implement page navigation UI: previous/next buttons, page indicator, keyboard shortcuts (arrow keys)
- [ ] 11.4 Implement batch progress display ("12/30 pages translated")

## 12. Integration & Polish

- [ ] 12.1 Wire up full pipeline: image load → OCR → bubble detect → order → translate → display
- [ ] 12.2 Implement language/engine selector in toolbar with re-translation on change
- [ ] 12.3 Add loading states and error handling throughout the UI
- [ ] 12.4 Add app icon and menu bar setup (File menu, Settings shortcut Cmd+,)
