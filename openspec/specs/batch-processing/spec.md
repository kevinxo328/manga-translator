## Purpose

Multi-page manga processing: folder/archive loading, background translation, and page navigation.

## Requirements

### Requirement: Open folders containing manga images
The system SHALL allow users to open a folder. The system SHALL scan the folder for image files (jpg, png, gif, webp, bmp) and sort them by filename for page ordering.

#### Scenario: Open manga folder
- **WHEN** user opens a folder containing 30 .jpg files named page_001.jpg through page_030.jpg
- **THEN** the system loads them as a 30-page manga, ordered by filename

### Requirement: Open compressed archives
The system SHALL support opening .zip and .cbz files. The system SHALL extract image files to a temporary directory within the sandbox container and treat them as a folder of pages.

#### Scenario: Open .cbz archive
- **WHEN** user opens a .cbz file containing manga pages
- **THEN** the system extracts images, sorts by filename, and presents as a multi-page manga

### Requirement: Progressive background translation
The system SHALL translate pages in the background using Swift concurrency. Pages SHALL become viewable as soon as their translation completes. The system SHALL limit concurrent translation tasks to avoid API rate limits.

#### Scenario: Browse while translating
- **WHEN** user opens a 30-page manga and translation begins
- **THEN** user can navigate to any page; completed pages show translations, pending pages show the original image with a loading indicator

#### Scenario: Concurrent translation limit
- **WHEN** batch translation is running
- **THEN** no more than 3 pages are being translated simultaneously

### Requirement: Page navigation
The system SHALL provide page navigation controls (previous/next buttons, page number indicator) when viewing multi-page manga. Keyboard shortcuts (left/right arrow keys) SHALL also navigate pages.

#### Scenario: Navigate pages
- **WHEN** user is on page 5 of 30 and presses the right arrow key
- **THEN** the view advances to page 6

#### Scenario: Page indicator
- **WHEN** user is viewing a multi-page manga
- **THEN** the UI shows "Page 5/30" with translation status (e.g., "Page 5/30 - Translated" or "Page 5/30 - Translating...")

### Requirement: Batch translation progress
The system SHALL display overall batch progress (e.g., "12/30 pages translated") during batch processing.

#### Scenario: Progress display
- **WHEN** 12 of 30 pages have been translated
- **THEN** the UI shows "12/30 pages translated"
