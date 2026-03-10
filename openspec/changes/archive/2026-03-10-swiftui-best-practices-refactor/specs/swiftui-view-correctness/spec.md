## ADDED Requirements

### Requirement: Views must not perform I/O in body
SwiftUI view `body` computed properties SHALL NOT perform synchronous file system reads, network calls, or other blocking I/O. All data required for rendering SHALL be pre-loaded and available as properties before `body` executes.

#### Scenario: ImageViewer renders with pre-loaded image
- **WHEN** `ImageViewer` is instantiated with a `MangaPage`
- **THEN** `page.image` is non-nil and the image renders without any disk access inside `body`

#### Scenario: ImageViewer receives nil image
- **WHEN** `ImageViewer` is instantiated and `page.image` is nil
- **THEN** the view renders a placeholder or empty state without attempting to load from disk

### Requirement: View ownership determines @StateObject vs @ObservedObject
A view that creates its own `ObservableObject` instance SHALL use `@StateObject` to retain ownership. A view that receives an injected `ObservableObject` SHALL use `@ObservedObject`.

#### Scenario: UpdateSettingsView retains its ViewModel across parent re-renders
- **WHEN** the parent view (`SettingsView`) re-renders
- **THEN** `UpdateSettingsView` retains the same `CheckForUpdatesViewModel` instance without recreating it

### Requirement: Interactive elements use Button for accessibility
Any view element that responds to user taps or clicks to perform an action SHALL use `Button` (or a control that inherits `Button` semantics) rather than a raw gesture recognizer. Custom appearance SHALL be achieved via `.buttonStyle`.

#### Scenario: Drop zone is accessible via VoiceOver
- **WHEN** VoiceOver is active and focus reaches the empty drop zone
- **THEN** VoiceOver announces it as a button with an appropriate label

#### Scenario: Translation card is accessible via VoiceOver
- **WHEN** VoiceOver is active and focus reaches a `TranslationCard`
- **THEN** VoiceOver announces it as a button that can be activated to highlight the bubble

#### Scenario: Bubble overlay is accessible via VoiceOver
- **WHEN** VoiceOver is active and focus reaches a `BubbleOverlay`
- **THEN** VoiceOver announces it as a button corresponding to the bubble number

### Requirement: onChange uses macOS 14+ two-argument closure
All `.onChange(of:)` modifiers SHALL use the two-argument closure form `{ oldValue, newValue in }` introduced in macOS 14 / iOS 17. The deprecated single-argument form SHALL NOT be used.

#### Scenario: onChange compiles without deprecation warnings
- **WHEN** the project is built targeting macOS 14+
- **THEN** no deprecation warnings are emitted for `onChange` usage

### Requirement: Computed values in body are minimal
`body` computed properties SHALL NOT create new array instances (e.g., via `sorted`, `filter`, `map`, `Array(enumerated())`) that can be precomputed. Stable derived values SHALL be declared as computed properties on the view struct.

#### Scenario: TranslationSidebar renders sorted translations without inline sort
- **WHEN** `TranslationSidebar.body` is evaluated
- **THEN** the sorted translation array is accessed from a computed property, not computed inline

### Requirement: All highlight state changes produce animation
Visual state changes driven by `isHighlighted` on `TranslationCard` SHALL animate regardless of whether the change was triggered by a tap gesture (with `withAnimation`) or programmatic state assignment (without `withAnimation`).

#### Scenario: Keyboard navigation animates card scale
- **WHEN** the user presses the down arrow key to move highlight to the next bubble
- **THEN** the previously highlighted card and newly highlighted card both animate their scale change

### Requirement: About window is a singleton
The About window SHALL be created once and reused. Subsequent activations of "About MangaTranslator" SHALL bring the existing window to front rather than creating a new `NSWindow` instance.

#### Scenario: About window opens once
- **WHEN** user clicks "About MangaTranslator" twice
- **THEN** only one About window exists; the second click brings the existing window to front
