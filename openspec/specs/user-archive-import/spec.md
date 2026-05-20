## Purpose

Defines the safe extraction boundary for user-imported ZIP and CBZ archives in `FileInputService`. Specifies validation rules for archive entries (path traversal, symlinks, hardlinks, special files, unparseable or unknown metadata), enforced size and count limits, per-import temporary directory lifecycle and cleanup, preservation of valid CBZ image scanning behavior, the external archive import error contract, low-sensitivity rejection diagnostics, and scope exclusions for the local model lifecycle.

## Requirements

### Requirement: Safely extract user ZIP and CBZ archives
The system SHALL extract user-imported ZIP and CBZ archives through a dedicated archive extraction boundary before image scanning. The extraction boundary SHALL validate archive entries before invoking extraction. The extraction boundary SHALL reject any archive that contains an absolute path, a `..` traversal component, a path whose standardized destination would escape the destination root, a symlink, a hardlink, a special file, an unknown entry type, or entry metadata that cannot be reliably parsed.

The system SHALL treat only regular file entries and directory entries as supported archive entry types. The system SHALL reject unsafe or unsupported entries before extracting archive contents.

#### Scenario: Reject path traversal entry
- **WHEN** a user imports a ZIP or CBZ archive containing an entry named `../escape.png`
- **THEN** archive extraction fails before the entry is extracted

#### Scenario: Reject absolute path entry
- **WHEN** a user imports a ZIP or CBZ archive containing an entry named `/tmp/escape.png`
- **THEN** archive extraction fails before the entry is extracted

#### Scenario: Reject destination escape after normalization
- **WHEN** a user imports a ZIP or CBZ archive containing an entry whose standardized destination path is outside the per-import destination root
- **THEN** archive extraction fails before the entry is extracted

#### Scenario: Reject symlink entry
- **WHEN** a user imports a ZIP or CBZ archive containing a symlink entry
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject hardlink entry
- **WHEN** a user imports a ZIP or CBZ archive containing a hardlink entry
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject special file entry
- **WHEN** a user imports a ZIP or CBZ archive containing a non-directory special file entry that is not a regular file
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject unparseable metadata
- **WHEN** the archive entry listing contains metadata that the extractor cannot parse into the required fixed fields
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject unknown entry type
- **WHEN** the archive entry listing contains an entry type that the extractor does not explicitly support
- **THEN** archive extraction fails before extracting archive contents

### Requirement: Enforce user archive size and count limits
The system SHALL enforce these default limits for user-imported ZIP and CBZ archives: at most 500 regular file entries, at most 25 * 1024 * 1024 bytes declared or actual size for any single regular file, and at most 500 * 1024 * 1024 bytes declared or actual total size across all regular files.

The system SHALL check file count and declared uncompressed sizes before extraction. The system SHALL check actual regular-file sizes again after extraction. Directory entries SHALL NOT count against the regular file count or regular-file size totals.

#### Scenario: Reject too many files before extraction
- **WHEN** a user imports a ZIP or CBZ archive containing more than 500 regular file entries
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject declared single file size over limit
- **WHEN** a user imports a ZIP or CBZ archive containing a regular file entry whose declared uncompressed size is greater than 25 * 1024 * 1024 bytes
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject declared total size over limit
- **WHEN** a user imports a ZIP or CBZ archive whose declared total uncompressed size across regular file entries is greater than 500 * 1024 * 1024 bytes
- **THEN** archive extraction fails before extracting archive contents

#### Scenario: Reject actual single file size over limit after extraction
- **WHEN** extraction produces a regular file whose actual size is greater than 25 * 1024 * 1024 bytes
- **THEN** archive extraction fails and the per-import temporary directory is removed

#### Scenario: Reject actual total size over limit after extraction
- **WHEN** extraction produces regular files whose actual total size is greater than 500 * 1024 * 1024 bytes
- **THEN** archive extraction fails and the per-import temporary directory is removed

### Requirement: Clean up failed user archive imports
The system SHALL create a unique per-import temporary directory for each user ZIP or CBZ import. The system SHALL remove the entire per-import temporary directory when archive extraction fails for any reason, including validation failure, unsupported entry type, size or count limit failure, extraction process failure, or post-extraction validation failure.

#### Scenario: Cleanup after validation failure
- **WHEN** a user imports an archive that fails pre-extraction validation
- **THEN** the per-import temporary directory for that import is removed

#### Scenario: Cleanup after extraction process failure
- **WHEN** the system extraction process returns a failure for a user ZIP or CBZ archive
- **THEN** the per-import temporary directory for that import is removed

#### Scenario: Cleanup after post-extraction validation failure
- **WHEN** a user archive passes pre-extraction validation but fails post-extraction filesystem validation
- **THEN** the per-import temporary directory for that import is removed

#### Scenario: No outside file created by malicious archive
- **WHEN** a user imports a malicious archive attempting to write outside the per-import destination root
- **THEN** no file is created or overwritten outside the per-import destination root

### Requirement: Preserve valid CBZ image scanning behavior
The system SHALL preserve existing valid CBZ import behavior after safe extraction. Valid archive imports SHALL continue to use `FileInputService.scanFolder(_:)` for image discovery. Image discovery SHALL recursively scan subdirectories, skip entries whose path components contain `__MACOSX`, include only files with extensions `jpg`, `jpeg`, `png`, `gif`, `webp`, `bmp`, `tiff`, or `tif` case-insensitively, and return image URLs sorted by `lastPathComponent.localizedStandardCompare`.

#### Scenario: Import valid CBZ with supported image extensions
- **WHEN** a user imports a valid CBZ containing files with supported image extensions
- **THEN** the system extracts the archive and returns image URLs for those supported images

#### Scenario: Recursively scan valid CBZ subdirectories
- **WHEN** a user imports a valid CBZ containing supported images inside nested directories
- **THEN** the system includes supported images from nested directories in the scan result

#### Scenario: Skip macOS metadata directory
- **WHEN** a user imports a valid CBZ containing images under a `__MACOSX` path component
- **THEN** the system excludes those `__MACOSX` images from the scan result

#### Scenario: Sort valid CBZ images by existing filename behavior
- **WHEN** a user imports a valid CBZ containing multiple supported images
- **THEN** the returned image URLs are sorted using `lastPathComponent.localizedStandardCompare`

### Requirement: Preserve external archive import error behavior
The system SHALL keep the external archive import error contract unchanged. `FileInputService.extractArchive(_:)` SHALL map archive extraction failures to `FileInputError.extractionFailed`. The system SHALL NOT introduce detailed user-facing archive rejection reasons as part of this change.

#### Scenario: User archive rejected with existing error
- **WHEN** a user ZIP or CBZ archive is rejected by the safe extraction boundary
- **THEN** `FileInputService.extractArchive(_:)` throws `FileInputError.extractionFailed`

#### Scenario: Internal rejection reason remains available to tests
- **WHEN** `ArchiveExtractor` rejects an unsafe archive in unit tests
- **THEN** the rejection reason can be asserted without changing the external `FileInputService` error contract

### Requirement: Log low-sensitivity archive rejection diagnostics
The system SHALL log low-sensitivity diagnostics for user archive extraction failures. Logs SHALL include the rejection category, relevant limit values, actual file counts or sizes when available, and the archive `lastPathComponent`. Logs SHALL NOT include full absolute paths or full archive entry paths. If an entry hint is logged, it SHALL be sanitized, truncated, and limited to a basename.

#### Scenario: Log rejection category without full paths
- **WHEN** a user archive is rejected by the safe extraction boundary
- **THEN** the diagnostic log includes the rejection category and archive `lastPathComponent` but does not include full absolute paths or full archive entry paths

#### Scenario: Log limit diagnostics
- **WHEN** a user archive is rejected for file count or size limits
- **THEN** the diagnostic log includes the applicable limit and observed count or size without logging full archive entry paths

### Requirement: Leave local model lifecycle untouched
The system SHALL NOT modify model download extraction, installed model files, active model directories, model download `UserDefaults`, or `ModelDownloadService` behavior as part of user archive extraction hardening.

#### Scenario: Task 3 does not change model download service
- **WHEN** the user archive extraction hardening change is implemented
- **THEN** `MangaTranslator/Services/ModelDownloadService.swift` behavior remains out of scope for the change

#### Scenario: Existing installed model is not affected by user archive import
- **WHEN** a user imports a ZIP or CBZ archive through `FileInputService`
- **THEN** installed local model files and persisted model download metadata are not modified by the user archive import flow
