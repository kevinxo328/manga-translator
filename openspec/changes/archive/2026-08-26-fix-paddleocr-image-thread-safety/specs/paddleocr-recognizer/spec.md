## ADDED Requirements

### Requirement: Transfer owned page image data across the OCR boundary
The system SHALL materialize an owned, pixel-backed image snapshot from each page `NSImage` on the main actor before background OCR begins. Background OCR service and recognizer APIs SHALL receive only that snapshot as a `CGImage` or equivalent immutable owned pixel buffer and MUST NOT convert or otherwise access the source `NSImage`. The snapshot SHALL remain retained for the complete page OCR attempt so detection, region cropping, and Core Image conversion are independent of SwiftUI display, image eviction, and the source `NSImage` lifetime.

#### Scenario: Page is displayed while high-accuracy OCR runs
- **WHEN** SwiftUI displays a page while background PaddleOCR processes its regions
- **THEN** OCR reads only the owned snapshot and completes or reports an OCR error without accessing the displayed `NSImage` or crashing because of concurrent image access

#### Scenario: Source image is released before worker processing
- **WHEN** the source `NSImage` is released or evicted after snapshot creation but before the background OCR service processes the page
- **THEN** detection, cropping, and Core Image conversion read valid pixels from the owned snapshot and do not depend on the source image's backing storage

#### Scenario: One page contains multiple OCR regions
- **WHEN** a page produces multiple detector regions for OCR
- **THEN** all regions use the same retained page snapshot and the system creates no additional full-page snapshot for each region

#### Scenario: Large page crosses the OCR boundary
- **WHEN** a 4K-or-larger page is submitted for high-accuracy OCR
- **THEN** the system creates at most one full-page owned pixel buffer for that in-flight page, keeps inference outside the UI-critical execution context after handoff, and does not terminate with an illegal memory access or out-of-memory crash

#### Scenario: Page image cannot be materialized
- **WHEN** the source page cannot be converted into an owned pixel snapshot
- **THEN** the system reports a descriptive OCR error before background inference begins and does not pass the source `NSImage` to the OCR service
