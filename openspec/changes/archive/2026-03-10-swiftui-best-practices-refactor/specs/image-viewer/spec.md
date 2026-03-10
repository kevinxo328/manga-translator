## MODIFIED Requirements

### Requirement: Display manga image with bubble overlays
The system SHALL display the loaded manga image on the left side of a split view. Detected bubble regions SHALL be marked with numbered indicators on the image. The image data SHALL be pre-loaded by the ViewModel before `ImageViewer` is instantiated; `ImageViewer` SHALL NOT perform any synchronous or asynchronous disk I/O.

#### Scenario: Image with detected bubbles
- **WHEN** a manga image is loaded and processed
- **THEN** the image is displayed with numbered bubble indicators overlaid at each detected bubble position

#### Scenario: Image pre-loaded before display
- **WHEN** the ViewModel transitions a page from pending to translated state
- **THEN** `page.image` is non-nil before `ImageViewer` renders the page
