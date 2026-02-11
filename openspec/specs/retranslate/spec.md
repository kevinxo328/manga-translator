## Purpose

Re-translate the current page using existing OCR results with current translation settings, bypassing cache lookup and OCR processing.

## Requirements

### Requirement: Re-translate current page from existing OCR results
The system SHALL provide a re-translate action that takes the current page's OCR results (extracted from the translated state) and runs translation with the current engine and language settings, bypassing both cache lookup and OCR processing.

#### Scenario: Successful re-translation
- **WHEN** user clicks the re-translate button while viewing a translated page
- **THEN** the system extracts OCR bubbles from the current translation, translates them using the active translation engine and language pair, updates the displayed translations, and overwrites the cache entry

#### Scenario: Re-translate with different engine
- **WHEN** user changes translation engine in the toolbar and clicks re-translate
- **THEN** the system translates existing OCR results using the newly selected engine and stores the result under the new engine's cache key

#### Scenario: Re-translate while no translations exist
- **WHEN** user views a page that has not been translated yet (pending or error state)
- **THEN** the re-translate button SHALL be disabled or hidden

### Requirement: Re-translate button in translation sidebar
The system SHALL display a re-translate button in the TranslationSidebar header area. The button SHALL be visible only when the current page has translations.

#### Scenario: Button visibility with translations
- **WHEN** the current page is in translated state
- **THEN** the re-translate button is visible and enabled in the sidebar header

#### Scenario: Button visibility without translations
- **WHEN** the current page is in pending, processing, or error state
- **THEN** the re-translate button is not visible or is disabled

### Requirement: Loading state during re-translation
The system SHALL indicate a loading state while re-translation is in progress. The page state SHALL transition to processing and back to translated upon completion.

#### Scenario: Loading indicator during re-translate
- **WHEN** user triggers re-translate
- **THEN** the UI shows a processing state until the new translation completes

#### Scenario: Error during re-translate
- **WHEN** re-translation fails (e.g., API error)
- **THEN** the system SHALL display the error and preserve the previous translation results
