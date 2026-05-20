## Why

User-imported ZIP/CBZ archives are untrusted input, but the current import path extracts them directly with `/usr/bin/unzip -o <archive> -d <tempDir>`. This leaves the app without an explicit safety boundary for path traversal, symlinks, hardlinks, special files, excessive file counts, or excessive uncompressed size.

This needs to be fixed before archive import remains a safe supported workflow, while preserving existing valid CBZ scanning behavior.

## What Changes

- Add a dedicated archive extraction boundary for user-imported ZIP/CBZ files.
- Validate archive entries before extraction and reject unsafe, unsupported, unknown, or unparseable entries.
- Enforce default limits for user archives: at most 500 files, at most 25 MiB per regular file, and at most 500 MiB total uncompressed regular-file content.
- Re-check extracted filesystem results after extraction for root confinement, regular-file type, per-file size, and total size.
- Ensure failed archive imports clean up the per-import UUID temporary directory.
- Preserve existing valid CBZ behavior: recursive image scanning, `__MACOSX` skipping, supported image extensions, and localized filename sorting.
- Add low-sensitivity diagnostic logging for archive rejection categories and limit values without logging full absolute paths or full entry paths.
- Do not change `ModelDownloadService`, installed model state, model download metadata, or active model directory behavior in this change.

## Capabilities

### New Capabilities

- `user-archive-import`: Safe extraction and scanning behavior for user-imported ZIP/CBZ archives.

### Modified Capabilities

- None.

## Impact

- Affected production code:
  - `MangaTranslator/Services/ArchiveExtractor.swift` will be added.
  - `MangaTranslator/Services/FileInputService.swift` will use the new extractor for ZIP/CBZ import.
- Affected tests:
  - `MangaTranslatorTests/ArchiveExtractorTests.swift` will be added.
  - `MangaTranslatorTests/TranslationViewModelTests.swift` may receive focused regression coverage if needed.
- Runtime behavior:
  - Malicious or unsupported archives fail import and surface the existing archive extraction failure behavior.
  - Valid CBZ imports continue to produce the same image scan results.
- Out of scope:
  - `MangaTranslator/Services/ModelDownloadService.swift`
  - Local model install atomicity
  - Downloaded model verification
  - User-facing detailed archive error messages
