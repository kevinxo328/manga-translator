## Why

The current SwiftUI views contain several correctness, performance, and accessibility issues identified in a code review: synchronous disk I/O in `body`, incorrect `@ObservedObject` ownership, deprecated `onChange` API usage, and use of `onTapGesture` where `Button` is required. Addressing these now improves reliability, accessibility compliance, and prepares the codebase for macOS 15+ API requirements.

## What Changes

- **ImageViewer**: Remove synchronous `NSImage(contentsOf:)` call from `body`; image must always be pre-loaded before the view renders
- **UpdateSettingsView**: Change `@ObservedObject` to `@StateObject` since the view creates and owns the object
- **About window**: Hold a strong reference to prevent memory leak on repeated clicks
- **onChange (4 files)**: Migrate all single-argument `onChange(of:)` closures to the macOS 14+ two-argument form
- **Accessibility**: Replace `onTapGesture` with `Button` in `ContentView` (drop zone), `TranslationSidebar` (cards), and `ImageViewer` (bubble overlays)
- **Performance**: Move inline `translations.sorted(...)` and `Array(enumerated())` calls out of `body` into computed properties in `TranslationSidebar` and `ImageViewer`
- **Animation**: Add `.animation(_:value:)` modifier to `TranslationCard.scaleEffect` so keyboard-driven highlight changes animate correctly

## Capabilities

### New Capabilities
- `swiftui-view-correctness`: Correct state ownership, lifecycle, and memory management rules for SwiftUI views in this app

### Modified Capabilities
- `image-viewer`: Pre-loaded image requirement — `page.image` must be non-nil before `ImageViewer` renders; synchronous fallback load is removed
- `settings-management`: `UpdateSettingsView` ownership model corrected to `@StateObject`

## Impact

- `MangaTranslator/Views/ImageViewer.swift` — remove disk I/O from body
- `MangaTranslator/Views/ContentView.swift` — fix `onChange`, fix drop zone accessibility
- `MangaTranslator/Views/SettingsView.swift` — fix `@ObservedObject` → `@StateObject`, fix `onChange`, About window ref
- `MangaTranslator/Views/TranslationSidebar.swift` — fix `onChange`, move sort to computed property, fix card accessibility, add animation modifier
- `MangaTranslatorApp.swift` — hold strong reference to About window
- All changes are non-breaking; no public API or data model changes
