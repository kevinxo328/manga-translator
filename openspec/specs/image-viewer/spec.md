## Purpose

Manga image display, bubble overlays, sidebar translations, and user interaction.
## Requirements
### Requirement: Display manga image with bubble overlays
The system SHALL display the loaded manga image on the left side of a split view. Detected bubble regions SHALL be marked with numbered indicators on the image. The image data for the displayed page SHALL be pre-loaded by the ViewModel before `ImageViewer` renders it; `ImageViewer` SHALL NOT perform any synchronous or asynchronous disk I/O.

The ViewModel SHALL keep decoded page images resident only for a sliding window of pages: the current page, its immediate neighbors (current ± 1), and any page with an open Edit Mode session. Pages outside the window MAY hold a nil image; their translated state and image hash SHALL be retained, and their image SHALL be reloaded from `imageURL` when the window reaches them (e.g., via page navigation).

The image MUST be scaled to fill the maximum available area (zoom-to-fit) regardless of the DPI metadata embedded in the image file. Scale calculations MUST use the image's pixel dimensions (from `NSBitmapImageRep.pixelsWide` / `pixelsHigh`), not `NSImage.size` (which is DPI-adjusted points). Bubble overlay positions MUST be computed using the same pixel dimensions as the reference coordinate space.

#### Scenario: Image with detected bubbles
- **WHEN** a manga image is loaded and processed
- **THEN** the image is displayed with numbered bubble indicators overlaid at each detected bubble position

#### Scenario: Image pre-loaded before display
- **WHEN** a page becomes the current page (on load or via next/previous navigation)
- **THEN** `page.image` is non-nil before `ImageViewer` renders the page

#### Scenario: Pages outside the sliding window release their bitmaps
- **WHEN** batch translation completes for a page outside the sliding window
- **THEN** that page's `page.image` is nil while its translated state and image hash are retained
- **AND** navigating to that page reloads the image before `ImageViewer` renders it

#### Scenario: High-DPI image fills viewer
- **WHEN** a 600 DPI image with pixel dimensions 1114×1600 is displayed in a 500×700 pt viewer area
- **THEN** the image is scaled to fill the viewer (scale ≈ 0.438, display ≈ 488×700 pt) rather than displaying at 133×192 pt

#### Scenario: Bubble overlay aligned to high-DPI image
- **WHEN** a bubble bounding box is at pixel x=500 on a 1114 px wide image displayed at 488 pt wide
- **THEN** the overlay x-position is 500 × (488 / 1114) ≈ 219 pt, not 500 × (488 / 133) ≈ 1835 pt

#### Scenario: 72 DPI image is unaffected
- **WHEN** a 72 DPI image where pixel dimensions equal point dimensions is displayed
- **THEN** display behaviour is identical to before this change

### Requirement: Hover popover showing translation
The system SHALL display a popover with the translated text when the user hovers over a detected bubble region on the image.

#### Scenario: Hover over bubble
- **WHEN** user moves the mouse over bubble region #2
- **THEN** a popover appears showing the translated text for bubble #2

#### Scenario: Mouse leaves bubble
- **WHEN** user moves the mouse away from a bubble region
- **THEN** the popover disappears

### Requirement: Sidebar translation list
The system SHALL display a sidebar on the right side showing all bubble translations in reading order. Each entry SHALL show the bubble number, original text, and translated text.

#### Scenario: Sidebar display
- **WHEN** translation completes for a page with 4 bubbles
- **THEN** the sidebar lists 4 entries in reading order, each with number, original text, and translation

### Requirement: Sidebar-to-image highlighting
The system SHALL highlight the corresponding bubble overlay on the image when the user clicks a translation entry in the sidebar.

#### Scenario: Click sidebar entry
- **WHEN** user clicks translation entry #3 in the sidebar
- **THEN** bubble #3 on the image is visually highlighted (e.g., colored border)

### Requirement: Image open via multiple methods
The system SHALL support opening images via: File menu (Cmd+O), drag-and-drop onto the app window, and paste from clipboard (Cmd+V).

#### Scenario: Drag and drop image
- **WHEN** user drags a .jpg file onto the app window
- **THEN** the image is loaded and processing begins

#### Scenario: Paste from clipboard
- **WHEN** user presses Cmd+V with an image in the clipboard
- **THEN** the image is loaded and processing begins

### Requirement: Language and engine selection
The system SHALL display source language, target language, and translation engine selectors in the UI. Changing any selector SHALL re-translate the current page (or load from cache if available).

#### Scenario: Switch translation engine
- **WHEN** user changes engine from DeepL to Claude while viewing a translated page
- **THEN** the system checks cache for Claude results; if not cached, re-translates using Claude

### Requirement: Edit-mode canvas overlay and gesture surface

When a page is in an active Edit Mode session (see `manual-bubble-editing`), `ImageViewer` SHALL render an edit-mode overlay layer above the existing `BubbleOverlay` layer. The overlay SHALL:

- Draw a 1.5 pt accent-colour border around every selected box.
- Draw unselected boxes using the same neutral border/fill vocabulary as the existing viewing-mode bubble overlay.
- Draw 8 handles per selected box (4 corners at 16×16 pt, 4 edge midpoints at 16×8 pt for top/bottom edges and 8×16 pt for left/right edges) positioned in display coordinates.
- Draw a dashed marquee outline during an in-flight Draw gesture, following the cursor in real time.
- Avoid using separate canvas colours for manually-flagged boxes (`isManual = true`) versus auto-detected boxes (`isManual = false`); manual state is tracked in data and surfaced through sidebar dirty-state decoration where needed.

`ImageViewer` SHALL route the edit interaction through a single `DragGesture(minimumDistance: 0)` state machine. The first `onChanged` event SHALL classify the gesture into exactly one of three modes:

1. **Empty-canvas drag** (gated by `onChanged`'s first event hit-testing outside all existing boxes' display rects) → Draw.
2. **Box-body drag** (gated by first event inside a box, outside handle zones) → Move.
3. **Handle drag** (gated by first event inside one of the 8 handle zones) → Resize.

This unified state machine replaces the earlier three-gesture `.simultaneousGesture(...)` design to avoid focus and cancellation races in SwiftUI while preserving the same user-visible routing rules.

Hit-testing SHALL use **display coordinates** (not image pixel coordinates), with handle zones rendered at the constant point sizes above regardless of image zoom.

`ImageViewer` SHALL NOT modify the working copy directly; every gesture SHALL forward its result through a callback exposed by the view to `TranslationViewModel`, which records the corresponding `EditAction`.

Outside Edit Mode, `ImageViewer`'s behaviour SHALL be identical to today's behaviour (no edit overlay, no edit gestures, no callbacks invoked).

#### Scenario: Selection handles render on selected boxes
- **WHEN** Edit Mode is active and box B is the only selected box
- **THEN** `ImageViewer` draws 8 handles positioned around B's display rect
- **AND** other boxes have no handles

#### Scenario: Empty-canvas drag does not move an existing box
- **WHEN** Edit Mode is active and the user starts a drag at a display coordinate outside every box's display rect
- **THEN** a Draw gesture begins
- **AND** no Move or Resize gesture is initiated

#### Scenario: Box-body drag moves only that box
- **WHEN** Edit Mode is active and the user starts a drag inside box A's body (outside A's handle zones)
- **THEN** a Move gesture for A begins
- **AND** no Draw or Resize gesture is initiated

#### Scenario: Handle drag resizes the corresponding edge
- **WHEN** Edit Mode is active and the user starts a drag inside box A's bottom-right corner handle
- **THEN** a Resize gesture begins adjusting A's right and bottom edges

#### Scenario: Manual and auto boxes share canvas styling
- **WHEN** Edit Mode is active, box A has `isManual = true`, and box B has `isManual = false`
- **THEN** A and B use the same unselected canvas border and fill styling
- **AND** selecting either box uses the same selected-box highlight and handles

#### Scenario: Viewing mode unchanged
- **WHEN** no Edit Mode session is active
- **THEN** `ImageViewer` renders today's overlays only
- **AND** no edit gestures fire
- **AND** the existing tap-to-highlight behaviour works unchanged

