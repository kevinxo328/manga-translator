## MODIFIED Requirements

### Requirement: Cache stores complete bubble data
The cache entry SHALL store the full bubble data as JSON: bubble bounding rects, original text, translated text, reading order, and the `isManual` flag. This avoids re-running OCR on cache hits and preserves user editing decisions across sessions.

The cache JSON encoder SHALL always emit an `isManual` key for every bubble entry.

The cache JSON decoder SHALL accept JSON entries that omit the `isManual` key by defaulting that field to `false`. Decoding SHALL NOT fail when reading entries written before this change.

No cache schema version bump or migration SHALL be required. The `translation_cache` SQLite table schema SHALL remain unchanged.

#### Scenario: Cached data completeness
- **WHEN** a cache entry is retrieved
- **THEN** it contains bubble positions, original text, translations, ordering, and the `isManual` flag for each bubble — sufficient to render the full UI without any reprocessing

#### Scenario: New write includes isManual
- **WHEN** the system writes a page to the cache after a successful Edit Mode Commit
- **THEN** every bubble's JSON contains an `isManual` key with the bubble's current Boolean value

#### Scenario: Old cache entry decodes with isManual defaulted to false
- **WHEN** the system reads a cache entry that was written before this change (no `isManual` key in JSON)
- **THEN** every bubble's `isManual` is decoded as `false`
- **AND** no decoding error is raised

#### Scenario: Round-trip preserves manual flag
- **WHEN** a page containing a manual bubble (`isManual = true`) is written to cache and then read back
- **THEN** the read-back bubble has `isManual = true`
