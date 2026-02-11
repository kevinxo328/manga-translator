## MODIFIED Requirements

### Requirement: Re-translate current page from existing OCR results
The system SHALL provide a re-translate action that performs a full OCR + translation pipeline on the current page using the current engine and language settings, bypassing cache lookup. The OCR step SHALL re-detect and re-recognize text from the page image. The translation step SHALL translate the fresh OCR results. The complete results SHALL be written back to cache, overwriting any existing entry.

#### Scenario: Successful re-translation with fresh OCR
- **WHEN** user clicks the re-translate button while viewing a translated page
- **THEN** the system performs OCR on the page image, translates the OCR results using the active translation engine and language pair, updates the displayed translations with the new results, and overwrites the cache entry

#### Scenario: Re-translate with different engine
- **WHEN** user changes translation engine in the toolbar and clicks re-translate
- **THEN** the system performs fresh OCR, translates using the newly selected engine, and stores the result under the new engine's cache key

#### Scenario: Re-translate while no translations exist
- **WHEN** user views a page that has not been translated yet (pending or error state)
- **THEN** the re-translate button SHALL be disabled or hidden

#### Scenario: Re-translate produces different OCR results
- **WHEN** re-translate OCR detects different text regions or text content than the original translation
- **THEN** the system SHALL use the new OCR results for translation and completely replace the previous cache entry with the new results
