## MODIFIED Requirements

### Requirement: Display manga image with bubble overlays
The system SHALL display the loaded manga image on the left side of a split view. Detected bubble regions SHALL be marked with numbered indicators on the image. The image data SHALL be pre-loaded by the ViewModel before `ImageViewer` is instantiated; `ImageViewer` SHALL NOT perform any synchronous or asynchronous disk I/O.

The image MUST be scaled to fill the maximum available area (zoom-to-fit) regardless of the DPI metadata embedded in the image file. Scale calculations MUST use the image's pixel dimensions (from `NSBitmapImageRep.pixelsWide` / `pixelsHigh`), not `NSImage.size` (which is DPI-adjusted points). Bubble overlay positions MUST be computed using the same pixel dimensions as the reference coordinate space.

#### Scenario: Image with detected bubbles
- **WHEN** a manga image is loaded and processed
- **THEN** the image is displayed with numbered bubble indicators overlaid at each detected bubble position

#### Scenario: Image pre-loaded before display
- **WHEN** the ViewModel transitions a page from pending to translated state
- **THEN** `page.image` is non-nil before `ImageViewer` renders the page

#### Scenario: High-DPI image fills viewer
- **WHEN** a 600 DPI image with pixel dimensions 1114×1600 is displayed in a 500×700 pt viewer area
- **THEN** the image is scaled to fill the viewer (scale ≈ 0.438, display ≈ 488×700 pt) rather than displaying at 133×192 pt

#### Scenario: Bubble overlay aligned to high-DPI image
- **WHEN** a bubble bounding box is at pixel x=500 on a 1114 px wide image displayed at 488 pt wide
- **THEN** the overlay x-position is 500 × (488 / 1114) ≈ 219 pt, not 500 × (488 / 133) ≈ 1835 pt

#### Scenario: 72 DPI image is unaffected
- **WHEN** a 72 DPI image where pixel dimensions equal point dimensions is displayed
- **THEN** display behaviour is identical to before this change
