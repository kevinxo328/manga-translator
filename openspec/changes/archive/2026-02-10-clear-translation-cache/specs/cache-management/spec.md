## ADDED Requirements

### Requirement: Clear all cached translations
The system SHALL provide a way to delete all rows from the `translation_cache` SQLite table via a single operation.

#### Scenario: Clear cache successfully
- **WHEN** `CacheService.clearAll()` is called
- **THEN** all rows in the `translation_cache` table SHALL be deleted
- **THEN** subsequent `lookup()` calls SHALL return `nil` for previously cached entries

### Requirement: Clear cache button in Settings
The system SHALL display a "Clear Cache" button in the Settings view Preferences tab.

#### Scenario: User taps Clear Cache
- **WHEN** user clicks the "Clear Cache" button
- **THEN** a confirmation alert SHALL be presented

#### Scenario: User confirms clearing
- **WHEN** user confirms the clear cache alert
- **THEN** all translation cache entries SHALL be deleted from disk
- **THEN** all loaded pages SHALL be reset to `.pending` state

#### Scenario: User cancels clearing
- **WHEN** user dismisses the confirmation alert
- **THEN** no cache data SHALL be modified

### Requirement: Reset page states after clearing
The system SHALL reset all in-memory `MangaPage.state` values to `.pending` after the cache is cleared, so that subsequent translation runs fresh OCR and translation.

#### Scenario: Pages reset after cache clear
- **WHEN** cache is cleared while pages are loaded
- **THEN** every page's state SHALL become `.pending`
- **THEN** no automatic re-translation SHALL be triggered
