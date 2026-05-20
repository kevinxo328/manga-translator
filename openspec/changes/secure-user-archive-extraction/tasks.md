## 1. Test Scaffolding

- [ ] 1.1 Add `MangaTranslatorTests/ArchiveExtractorTests.swift` with isolated temporary test directories and cleanup.
- [ ] 1.2 Add a test-only ZIP writer helper that can create regular file entries, directory entries, path traversal names, absolute path names, symlink metadata, hardlink metadata, unsupported entry types, and declared uncompressed sizes without committing binary fixtures.
- [ ] 1.3 Add assertions that verify no file is created outside the intended destination root and that the per-import UUID temporary directory is removed on failure.

## 2. Pre-Extraction Safety Tests

- [ ] 2.1 Write failing test `rejectsPathTraversalEntries` for an entry named `../escape.png`.
- [ ] 2.2 Write failing test `rejectsAbsolutePathEntries` for an entry named `/tmp/escape.png`.
- [ ] 2.3 Write failing test `rejectsSymlinkEntries` for a symlink entry.
- [ ] 2.4 Write failing test `rejectsHardlinkEntries` for a hardlink entry.
- [ ] 2.5 Write failing test `rejectsUnsupportedSpecialFileEntries` for a non-directory special file entry that is not a regular file.
- [ ] 2.6 Write failing test `rejectsUnknownOrUnparseableEntries` for metadata the parser cannot reliably parse.

## 3. Limit Tests

- [ ] 3.1 Write failing test `rejectsTooManyFiles` for more than 500 regular file entries.
- [ ] 3.2 Write failing test `rejectsSingleUncompressedSizeOverLimit` for declared uncompressed size greater than 25 * 1024 * 1024 bytes.
- [ ] 3.3 Write failing test `rejectsTotalUncompressedSizeOverLimit` for declared total uncompressed size greater than 500 * 1024 * 1024 bytes.
- [ ] 3.4 Write failing test for post-extraction actual single file size greater than 25 * 1024 * 1024 bytes.
- [ ] 3.5 Write failing test for post-extraction actual total regular-file size greater than 500 * 1024 * 1024 bytes.

## 4. Valid Import Regression Tests

- [ ] 4.1 Write failing test `extractsValidCBZAndFileInputServiceScansImages` for a valid CBZ containing supported image extensions.
- [ ] 4.2 Verify valid CBZ scanning recurses into subdirectories.
- [ ] 4.3 Verify valid CBZ scanning skips `__MACOSX` path components.
- [ ] 4.4 Verify valid CBZ results use `lastPathComponent.localizedStandardCompare` sorting.
- [ ] 4.5 Verify `FileInputService.extractArchive(_:)` maps extractor failures to `FileInputError.extractionFailed`.

## 5. ArchiveExtractor Implementation

- [ ] 5.1 Add `MangaTranslator/Services/ArchiveExtractor.swift`.
- [ ] 5.2 Define `ArchiveExtractor.Limits` with defaults: `maxFiles = 500`, `maxSingleFileBytes = 25 * 1024 * 1024`, `maxTotalBytes = 500 * 1024 * 1024`.
- [ ] 5.3 Define precise internal extractor errors for unsafe path, unsupported entry type, unparseable metadata, file count limit, single file size limit, total size limit, extraction process failure, and post-extraction validation failure.
- [ ] 5.4 Implement entry listing with `/usr/bin/zipinfo -l` or `/usr/bin/unzip -Z -l`.
- [ ] 5.5 Implement structured parsing for the chosen listing format; reject any entry line that cannot be parsed into the required fields.
- [ ] 5.6 Implement pre-extraction validation for absolute paths, `..` traversal components, standardized destination root confinement, symlinks, hardlinks, unsupported special files, unknown entry types, file count, declared single file size, and declared total regular-file size.
- [ ] 5.7 Implement extraction into the provided destination root only after pre-extraction validation succeeds.
- [ ] 5.8 Implement post-extraction filesystem validation using resolved and standardized URLs, regular-file checks, root confinement checks, actual single file sizes, and actual total regular-file size.
- [ ] 5.9 Add low-sensitivity `os.Logger` diagnostics that include rejection category, limits, observed counts/sizes, and archive `lastPathComponent`, without logging full absolute paths or full entry paths.

## 6. FileInputService Integration

- [ ] 6.1 Update `FileInputService.extractArchive(_:)` to create the per-import UUID temporary directory and call `ArchiveExtractor`.
- [ ] 6.2 Ensure `FileInputService.extractArchive(_:)` removes the entire per-import UUID temporary directory on any extractor or process failure.
- [ ] 6.3 Ensure `FileInputService.extractArchive(_:)` returns the same per-import UUID temporary directory on success.
- [ ] 6.4 Ensure `FileInputService.extractArchive(_:)` throws `FileInputError.extractionFailed` for archive extraction failures.
- [ ] 6.5 Do not modify `MangaTranslator/Services/ModelDownloadService.swift`.

## 7. Verification

- [ ] 7.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/ArchiveExtractorTests`.
- [ ] 7.2 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/TranslationViewModelTests`.
- [ ] 7.3 Confirm malicious archive tests do not create or overwrite files outside the destination root.
- [ ] 7.4 Confirm failed archive imports remove the per-import UUID temporary directory.
- [ ] 7.5 Confirm valid CBZ imports preserve existing image extension filtering, recursive scanning, `__MACOSX` skipping, and localized filename sorting.
- [ ] 7.6 Confirm `git diff -- MangaTranslator/Services/ModelDownloadService.swift` is empty for this change.
