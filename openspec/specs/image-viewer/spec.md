## Purpose

Manga image display, bubble overlays, sidebar translations, and user interaction.

## Requirements

### Requirement: Display manga image with bubble overlays
The system SHALL display the loaded manga image on the left side of a split view. Detected bubble regions SHALL be marked with numbered indicators on the image.

#### Scenario: Image with detected bubbles
- **WHEN** a manga image is loaded and processed
- **THEN** the image is displayed with numbered bubble indicators overlaid at each detected bubble position

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
