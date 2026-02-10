## Purpose

SQLite-based caching of translation results to avoid redundant API calls.

## Requirements

### Requirement: Cache translation results in SQLite
The system SHALL store translation results in a SQLite database within the app's sandboxed container. The cache key SHALL be the combination of (image SHA256 hash, source language, target language, translation engine).

#### Scenario: Cache hit
- **WHEN** user opens an image that was previously translated with the same language pair and engine
- **THEN** the system loads cached results instantly without calling OCR or translation API

#### Scenario: Cache miss
- **WHEN** user opens an image not in cache (or with different language/engine settings)
- **THEN** the system runs the full OCR → translate pipeline and stores the result in cache

### Requirement: Cache stores complete bubble data
The cache entry SHALL store the full bubble data as JSON: bubble bounding rects, original text, translated text, and reading order. This avoids re-running OCR on cache hits.

#### Scenario: Cached data completeness
- **WHEN** a cache entry is retrieved
- **THEN** it contains bubble positions, original text, translations, and ordering — sufficient to render the full UI without any reprocessing

### Requirement: Cache auto-invalidation on image change
The system SHALL use SHA256 hash of the image file contents as part of the cache key. If the image file is modified, the hash changes and the old cache entry is naturally bypassed.

#### Scenario: Image file modified
- **WHEN** user modifies an image file and reopens it
- **THEN** the system computes a new hash, finds no cache match, and re-processes the image

### Requirement: Cache cleanup on uninstall
The SQLite database SHALL reside within the app's sandboxed container directory. When the app is removed via Launchpad or App Store, the container and all cached data SHALL be automatically deleted by macOS.

#### Scenario: App uninstall
- **WHEN** user deletes the app via Launchpad
- **THEN** the SQLite database and all cached translations are removed automatically
