## Context

Greenfield macOS app project. Current repo contains only a placeholder Python script. We are replacing it with a native SwiftUI application.

The app translates manga speech bubbles using macOS Vision for OCR and cloud APIs for translation. Target users are manga readers who want to read untranslated works in Japanese, English, or Traditional Chinese.

Constraints:
- macOS 13+ (Vision framework Japanese OCR maturity)
- Sandboxed (for clean uninstall + potential App Store distribution)
- Minimal app size (leverage system frameworks, no bundled ML models)
- User must provide their own API keys for translation services

## Goals / Non-Goals

**Goals:**
- Accurate speech bubble detection and grouping from manga images
- Context-aware translation by sending full-page bubble context to LLMs
- Fast re-display of previously translated pages via SQLite cache
- Clean, native macOS UI with image viewer + sidebar + hover overlays
- Support batch processing of folders and .zip/.cbz archives

**Non-Goals:**
- In-place image editing (no text removal or redrawing on the image)
- Panel/frame detection for v1 (reading order uses bubble positions + LLM correction)
- Offline translation (all translation backends are cloud-based)
- iOS/iPadOS support
- Manga downloading or library management
- OCR training or custom ML models

## Decisions

### D1: SwiftUI over AppKit

**Choice**: SwiftUI with macOS 13+ deployment target

**Rationale**: SwiftUI provides declarative UI, built-in support for `.onHover`, `popover`, `HSplitView`, drag-and-drop. macOS 13 is mature enough for our needs. AppKit would offer more control but significantly more boilerplate.

**Alternatives**: AppKit (more control, harder to write), Electron (cross-platform but huge bundle), Python GUI (poor native feel).

### D2: Spatial clustering for bubble detection (no ML model)

**Choice**: Agglomerative clustering of Vision text observations using relative distance thresholds.

**Rationale**: Vision framework detects individual text regions. Manga speech bubbles contain multiple text lines that are spatially close. By clustering text observations where inter-box distance < 2x character height, we group lines belonging to the same bubble. This avoids bundling any ML model.

**Algorithm**:
1. Run `VNRecognizeTextRequest` to get all text observations with bounding boxes
2. Convert normalized coordinates (Vision: bottom-left origin) to image coordinates (top-left origin)
3. For each pair of text boxes, compute distance between nearest edges
4. Merge boxes where distance < threshold (2x median character height)
5. Each merged cluster = one bubble; union of boxes = bubble bounding rect

**Alternatives**: YOLO-based bubble detector (accurate but adds ~20MB model), contour detection (brittle with varying art styles).

### D3: LLM-assisted reading order

**Choice**: Two-phase ordering — spatial heuristic first, then LLM correction.

**Phase 1 (spatial)**: Sort bubbles by position using manga reading convention (right-to-left, top-to-bottom). Partition into rows by Y-overlap, then sort each row right-to-left.

**Phase 2 (LLM)**: When using an LLM translation backend, include bubble coordinates in the prompt and ask the LLM to reorder if the dialogue flow seems wrong. The LLM can use semantic cues (question before answer) to correct ordering errors.

For non-LLM backends (DeepL, Google), only Phase 1 is used.

**Alternatives**: Panel detection via edge detection (complex, fragile), manual reordering UI (adds complexity).

### D4: Translation service protocol with whole-page context

**Choice**: Swift protocol `TranslationService` with method signature:
```
func translate(bubbles: [BubbleText], from: Language, to: Language) async throws -> [TranslatedBubble]
```

All backends receive the full list of bubbles for a page. Traditional APIs (DeepL, Google) translate each bubble independently within the method. LLM backends (OpenAI, Claude) send all bubbles in a single request with positional context for better coherence.

LLM prompt returns JSON array for stable parsing:
```json
[
  {"index": 0, "translation": "..."},
  {"index": 1, "translation": "..."}
]
```

**Alternatives**: Translate one bubble at a time (loses context), streaming translation (adds complexity for marginal UX benefit in v1).

### D5: SQLite for translation cache

**Choice**: Raw SQLite3 via Swift's C API (no ORM).

**Schema**:
- `translation_cache`: keyed by (image_hash, source_lang, target_lang, engine) → stores full bubble data as JSON (positions + original text + translations)
- `history`: recent files/folders for quick re-open

**Rationale**: SQLite3 is a system library on macOS (zero bundle size impact). The data model is simple enough that an ORM adds no value. Image hash (SHA256) ensures cache invalidation when source image changes.

**Alternatives**: Core Data (heavy for this use case), JSON files (poor query performance at scale), SwiftData (requires macOS 14+).

### D6: Keychain for API keys

**Choice**: Store API keys in macOS Keychain via Security framework.

**Rationale**: Keychain is encrypted at rest, survives app updates, and is the macOS-standard way to store secrets. UserDefaults would store keys in a plist file readable by anyone with disk access.

### D7: Archive extraction for .cbz/.zip

**Choice**: Use Foundation's `FileManager` with `Process` calling `/usr/bin/unzip`, or Apple's `AppleArchive` framework.

**Rationale**: .cbz files are just .zip files with image contents. macOS ships with unzip. For sandboxed apps, we can use `NSFileCoordinator` or extract to a temporary directory within the sandbox container.

**Alternatives**: Third-party zip library (adds dependency), requiring users to extract manually (poor UX).

### D8: Progressive batch translation

**Choice**: Use Swift concurrency (`TaskGroup`) to process pages. Each page goes through OCR → translate pipeline. UI observes an `@Published` array of page states (pending/translating/done). User can browse pages freely; completed pages show translations immediately.

**Rationale**: Swift's structured concurrency makes this straightforward. Limit concurrent translations (e.g., 3 at a time) to avoid API rate limits.

## Risks / Trade-offs

**[Bubble clustering accuracy]** → Spatial clustering may merge nearby bubbles or split a single bubble with wide line spacing. Mitigation: Use adaptive threshold based on median character height; allow manual correction in future version.

**[Vision OCR quality for stylized manga fonts]** → Vision may struggle with heavily stylized or handwritten manga text. Mitigation: This is a system-level limitation; no mitigation in v1. Could add alternative OCR backend (e.g., Google Cloud Vision) in future.

**[LLM JSON parsing failures]** → LLM may not always return valid JSON. Mitigation: Wrap in try/catch with retry (up to 2 retries). If still failing, fall back to line-by-line text parsing.

**[Coordinate system complexity]** → Vision uses normalized bottom-left origin; SwiftUI uses top-left. Image may be scaled in the view. Mitigation: Create a single `CoordinateConverter` utility that handles all transformations in one place.

**[API rate limits during batch processing]** → Translating 30+ pages quickly may hit rate limits. Mitigation: Configurable concurrency limit; exponential backoff on 429 responses.

**[Sandbox file access]** → Sandboxed apps need explicit user permission to access files. Mitigation: Use `NSOpenPanel` / `.fileImporter` for file selection, which grants temporary access. For batch processing, request folder access which covers all contained files.
