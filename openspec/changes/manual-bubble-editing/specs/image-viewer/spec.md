## ADDED Requirements

### Requirement: Edit-mode canvas overlay and gesture surface

When a page is in an active Edit Mode session (see `manual-bubble-editing`), `ImageViewer` SHALL render an edit-mode overlay layer above the existing `BubbleOverlay` layer. The overlay SHALL:

- Draw a 1.5 pt accent-colour border around every selected box.
- Draw 8 handles per selected box (4 corners at 16×16 pt, 4 edge midpoints at 16×8 pt for top/bottom edges and 8×16 pt for left/right edges) positioned in display coordinates.
- Draw a dashed marquee outline during an in-flight Draw gesture, following the cursor in real time.
- Visually distinguish manually-flagged boxes (`isManual = true`) from auto-detected boxes (`isManual = false`) with a stable colour difference (e.g. solid border for manual, dashed for auto). This decoration SHALL coexist with selection highlight.

`ImageViewer` SHALL compose three `DragGesture`s with `.simultaneousGesture(...)`:

1. **Empty-canvas drag** (gated by `onChanged`'s first event hit-testing outside all existing boxes' display rects) → Draw.
2. **Box-body drag** (gated by first event inside a box, outside handle zones) → Move.
3. **Handle drag** (gated by first event inside one of the 8 handle zones) → Resize.

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

#### Scenario: Manual vs auto visual distinction
- **WHEN** Edit Mode is active, box A has `isManual = true`, and box B has `isManual = false`
- **THEN** A and B are rendered with visually distinct border styles
- **AND** the distinction is preserved regardless of which one is currently selected

#### Scenario: Viewing mode unchanged
- **WHEN** no Edit Mode session is active
- **THEN** `ImageViewer` renders today's overlays only
- **AND** no edit gestures fire
- **AND** the existing tap-to-highlight behaviour works unchanged
