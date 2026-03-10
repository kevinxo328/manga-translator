## Context

A code review of the SwiftUI view layer identified correctness, accessibility, deprecated API, and performance issues across 5 files. This is a purely view-layer refactor with no model, service, or data format changes. The app targets macOS 14+.

## Goals / Non-Goals

**Goals:**
- Eliminate synchronous disk I/O from view `body` methods
- Fix `@ObservedObject` vs `@StateObject` ownership error in `UpdateSettingsView`
- Prevent About window memory leak in `MangaTranslatorApp`
- Migrate all `onChange(of:)` closures to the macOS 14+ two-argument form
- Replace `onTapGesture` with `Button` where the element represents a user action (VoiceOver compliance)
- Move inline sort/enumeration out of `body` into computed properties
- Add `.animation(_:value:)` to `TranslationCard` so all highlight paths animate

**Non-Goals:**
- Changing business logic, translation pipeline, or data models
- Adopting `@Observable` / Observation framework (would be a separate larger refactor)
- Adding new UI features or behavior

## Decisions

### D1: Image pre-loading ownership — ViewModel, not ImageViewer

**Decision**: `TranslationViewModel` (not `ImageViewer`) is responsible for ensuring `page.image` is always non-nil before a page is displayed. `ImageViewer` treats `page.image` as a precondition and renders only what it receives.

**Rationale**: The ViewModel already owns the async loading pipeline. Pushing a lazy fallback into the view creates hidden async work inside `body` (not allowed) or requires the view to own its own loading state (scope creep). Keeping it in the ViewModel keeps views passive.

**Alternative considered**: Add `@State var loadedImage` to `ImageViewer` with `onAppear` async load. Rejected because it splits image loading across two layers and adds view state for what is fundamentally model state.

### D2: `@StateObject` for `UpdateSettingsView`

**Decision**: Change `@ObservedObject private var checkForUpdatesViewModel` to `@StateObject` in `UpdateSettingsView`.

**Rationale**: `UpdateSettingsView.init` creates the `CheckForUpdatesViewModel` instance directly. SwiftUI's rule: the view that *creates* an `ObservableObject` must use `@StateObject` to retain it across re-renders. `@ObservedObject` would allow SwiftUI to destroy and recreate the object on parent re-renders.

### D3: Strong reference for About window in App struct

**Decision**: Store the `NSWindow` as a property on `MangaTranslatorApp`. On subsequent clicks, bring the existing window to front instead of creating a new one.

**Rationale**: Current code creates a new `NSWindow` each click with no owner reference. With `isReleasedWhenClosed = false` but no strong reference in Swift, the window is owned only by AppKit's window list but cannot be closed cleanly and the old instances accumulate.

### D4: Accessibility — `Button` over `onTapGesture`

**Decision**: Replace all `onTapGesture` on interactive elements with `Button`. Use `.buttonStyle(.plain)` or `.buttonStyle(.borderless)` where custom appearance is required.

**Rationale**: `Button` participates in the macOS accessibility tree automatically. VoiceOver announces it as a button, focus rings work, keyboard activation works. `onTapGesture` provides none of these.

### D5: TDD approach — tests first, then implementation

**Decision**: For each fix, write a failing test (or failing UI test assertion) that captures the correct behavior before modifying the implementation.

**Rationale**: These are refactors — behavior must remain identical. Tests written first confirm the expected behavior is documented and that the fix does not regress other paths.

## Risks / Trade-offs

- **Image pre-loading scope**: Ensuring `page.image` is always pre-populated requires auditing all code paths that set `MangaPage.image`. If a path is missed, `ImageViewer` will receive a nil image. Mitigation: add a guard/assertion in `ImageViewer.body` during development.
- **About window singleton pattern**: Storing `NSWindow?` on `MangaTranslatorApp` (a struct) requires a class-based wrapper or using `@State`/`@StateObject`. Use a small private class wrapper to hold the reference.
- **`onChange` migration**: The two-argument closure receives `(oldValue, newValue)`. Code that ignores both arguments (like `ContentView:374`) just needs an empty `{ _, _ in }` closure. Verify each call site still compiles.

## Migration Plan

1. Write tests for each targeted behavior (TDD step)
2. Fix `@StateObject` in `UpdateSettingsView` (smallest, most isolated)
3. Fix About window strong reference
4. Migrate `onChange` in all four files
5. Replace `onTapGesture` with `Button` across three views
6. Move sort/enumeration to computed properties
7. Add animation modifier to `TranslationCard`
8. Fix image pre-loading: audit ViewModel, remove fallback from `ImageViewer`
9. Run all tests; verify UI manually
