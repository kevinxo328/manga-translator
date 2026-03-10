## 1. Fix @StateObject Ownership in UpdateSettingsView

- [x] 1.1 Write a test verifying `CheckForUpdatesViewModel` conforms to `ObservableObject` and can be initialized with an `SPUUpdater`
- [x] 1.2 Change `@ObservedObject private var checkForUpdatesViewModel` to `@StateObject` in `UpdateSettingsView`
- [x] 1.3 Verify the project builds with no warnings related to `UpdateSettingsView`

## 2. Fix About Window Memory Leak

- [x] 2.1 Write a test verifying that calling the about window action twice does not create two separate `NSWindow` instances (mock or inspect window count)
- [x] 2.2 Add a private `var aboutWindow: NSWindow?` property (wrapped in a reference type) to `MangaTranslatorApp`
- [x] 2.3 In the `CommandGroup` action, reuse the existing window if non-nil (call `makeKeyAndOrderFront`), otherwise create and store a new one
- [x] 2.4 Verify the test from 2.1 passes

## 3. Migrate Deprecated onChange API

- [x] 3.1 Write a test (or enable strict concurrency warnings as a build check) confirming zero deprecation warnings at build time for `onChange`
- [x] 3.2 Update `ContentView.swift:374` — `onChange(of: viewModel.preferences.translationEngine) { _ in ... }` → `{ _, _ in ... }`
- [x] 3.3 Update `SettingsView.swift:41` — `onChange(of: deepLKey) { newValue in ... }` → `{ _, newValue in ... }`
- [x] 3.4 Update `SettingsView.swift:51` — `onChange(of: googleKey) { newValue in ... }` → `{ _, newValue in ... }`
- [x] 3.5 Update `SettingsView.swift:61` — `onChange(of: openAIKey) { newValue in ... }` → `{ _, newValue in ... }`
- [x] 3.6 Update `TranslationSidebar.swift:67` — `onChange(of: highlightedBubbleId) { newId in ... }` → `{ _, newId in ... }`
- [x] 3.7 Update `TranslationSidebar.swift:73` — `onChange(of: pageId) { _ in ... }` → `{ _, _ in ... }`
- [x] 3.8 Build project and confirm zero `onChange` deprecation warnings

## 4. Replace onTapGesture with Button for Accessibility

- [x] 4.1 Write a test or ViewInspector check confirming the drop zone contains a `Button` element
- [x] 4.2 In `ContentView.dropZone`, replace `.onTapGesture { showFileImporter = true }` with `Button { showFileImporter = true } label: { ... }` and apply appropriate button style
- [x] 4.3 Write a test or ViewInspector check confirming `TranslationCard` is wrapped in a `Button`
- [x] 4.4 In `TranslationSidebar`, replace `.onTapGesture` on `TranslationCard` with a `Button` wrapper using `.buttonStyle(.plain)`; keep `withAnimation` inside the action
- [x] 4.5 Write a test or ViewInspector check confirming `BubbleOverlay` is wrapped in a `Button`
- [x] 4.6 In `ImageViewer`, replace `.onTapGesture` on image and bubble overlays with `Button` wrappers using `.buttonStyle(.plain)`
- [x] 4.7 Build and verify no regressions in visual appearance or tap behavior

## 5. Move Inline Sort to Computed Properties

- [x] 5.1 Write a test for `TranslationSidebar` confirming `sortedTranslations` returns bubbles in ascending `index` order
- [x] 5.2 Extract `translations.sorted(by: { $0.index < $1.index })` from `TranslationSidebar.body` into a `private var sortedTranslations: [TranslatedBubble]` computed property
- [x] 5.3 Replace `Array(sorted.enumerated())` with `Array(sortedTranslations.enumerated())` and remove the inline `let sorted` binding
- [x] 5.4 Write a test for `ImageViewer` confirming bubble overlay positions correspond to reading order
- [x] 5.5 Extract `translations.sorted(...)` in `ImageViewer.body` into a `private var sortedTranslations` computed property
- [x] 5.6 Verify both views build and render correctly

## 6. Add Animation Modifier to TranslationCard

- [x] 6.1 Write a test confirming `TranslationCard` has an animation modifier bound to `isHighlighted`
- [x] 6.2 Add `.animation(.spring(response: 0.3), value: isHighlighted)` to the `scaleEffect` modifier chain on `TranslationCard`
- [x] 6.3 Manually verify that pressing arrow keys to navigate bubbles animates the card scale (keyboard nav does not wrap in `withAnimation`)

## 7. Fix Image Pre-loading (Remove Disk I/O from ImageViewer.body)

- [x] 7.1 Write a test for `TranslationViewModel.loadImage(_:)` confirming `page.image` is non-nil after the call completes
- [x] 7.2 Write a test for `TranslationViewModel.loadFolder(_:)` confirming all loaded `MangaPage` instances have non-nil `image`
- [x] 7.3 Write a test for `TranslationViewModel.loadArchive(_:)` confirming all extracted pages have non-nil `image`
- [x] 7.4 Audit `TranslationViewModel` load methods and ensure `page.image` is set (loaded into memory) before appending to `pages`
- [x] 7.5 Remove the fallback `?? NSImage(contentsOf: page.imageURL)` from `ImageViewer.body`
- [x] 7.6 Add a `guard let image = page.image else { return }` (or equivalent empty state) in `ImageViewer.body` for defensive nil handling
- [x] 7.7 Run all tests from 7.1–7.3 and confirm they pass
- [x] 7.8 Manually load a single image, a folder, and a ZIP archive to verify images still display correctly
