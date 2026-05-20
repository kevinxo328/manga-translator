## Context

`FileInputService.extractArchive(_:)` currently creates a per-import temporary directory under `FileManager.default.temporaryDirectory/MangaTranslator/<UUID>` and invokes `/usr/bin/unzip -o <archive> -d <tempDir>` directly. `TranslationViewModel` then scans the returned directory through `FileInputService.scanFolder(_:)`.

That flow treats user-imported ZIP/CBZ archives as trusted enough to hand to `unzip` without an explicit pre-extraction safety boundary. The imported archive can be crafted by an external party, so the extraction boundary must reject entries that cannot be proven safe before any extraction occurs.

This change is scoped to user archive import only. `ModelDownloadService` has related extraction risks, but model install also involves checksum, active model directory, install atomicity, and persisted download state. Those concerns remain in the separate model lifecycle work.

## Goals / Non-Goals

**Goals:**

- Add an `ArchiveExtractor` service dedicated to safe extraction of user-imported ZIP/CBZ archives.
- Keep `FileInputService.extractArchive(_:)` as the app-facing entry point for user archive import.
- Preserve the existing success path shape: `FileInputService.extractArchive(_:)` creates and returns the per-import UUID temporary directory.
- Reject archive entries that are unsafe, unsupported, unknown, or not reliably parseable before extraction.
- Enforce fixed default user archive limits:
  - `maxFiles = 500`
  - `maxSingleFileBytes = 25 * 1024 * 1024`
  - `maxTotalBytes = 500 * 1024 * 1024`
- Validate both declared uncompressed sizes before extraction and actual regular-file sizes after extraction.
- Clean up the entire per-import UUID temporary directory on any failure.
- Preserve existing valid CBZ scanning behavior.
- Add low-sensitivity logs for diagnosis without exposing full untrusted paths.

**Non-Goals:**

- Do not modify `ModelDownloadService`.
- Do not modify installed model files, model download state, model `UserDefaults`, or active model directory behavior.
- Do not introduce detailed user-facing archive error messages in this change.
- Do not add a new third-party ZIP dependency for Task 3.
- Do not change image extension support or image sorting behavior.

## Decisions

### Decision: Keep `FileInputService` responsible for import directory lifecycle

`FileInputService.extractArchive(_:)` SHALL create the per-import UUID temporary directory, call `ArchiveExtractor`, return that directory on success, and remove that directory on failure.

Rationale:

- The temp path policy is app-specific and already belongs to `FileInputService`.
- The caller-facing behavior stays compatible with the current `TranslationViewModel` flow.
- `ArchiveExtractor` remains reusable for future work because it does not own app-specific temp path policy.

Alternative considered: make `ArchiveExtractor` create and return temp directories. This was rejected because it mixes generic extraction safety with MangaTranslator-specific temp directory ownership.

### Decision: Extract directly into the per-import UUID temp directory after preflight validation

For Task 3, the destination root passed to `ArchiveExtractor` is the per-import UUID temporary directory created by `FileInputService`. The extractor SHALL validate every entry before extraction and then invoke extraction into that destination root.

Rationale:

- The destination root is already isolated and unique per import.
- The operation either succeeds and returns the directory, or fails and `FileInputService` deletes the whole UUID directory.
- Adding a separate final directory or move step would not improve the user archive workflow and would create unnecessary overlap with model install atomicity.

Alternative considered: extract into a staging directory and move to a final directory. This was rejected for Task 3 because atomic install semantics belong to model download work, not temporary user CBZ import.

### Decision: Use system ZIP metadata tools with conservative parsing

`ArchiveExtractor` SHALL list entries before extraction using `/usr/bin/zipinfo -l` or `/usr/bin/unzip -Z -l`. The implementation SHALL parse fixed fields structurally. If any entry line cannot be parsed reliably, lacks required fields, has an unknown type, or exposes a type outside regular file or directory, extraction SHALL fail before invoking unzip.

Rationale:

- Avoids adding a third-party dependency for this narrow safety fix.
- Allows deterministic tests for the parser and rejection behavior.
- Preserves current reliance on system unzip tools while adding a safety boundary before extraction.

Alternative considered: introduce a Swift ZIP library. This was rejected for Task 3 because dependency selection and Xcode package integration would expand the change. A future change can revisit this if system tool parsing proves insufficient.

Alternative considered: skip preflight and only inspect the extracted filesystem. This was rejected because path traversal, special entries, and oversized payloads can cause damage or resource exhaustion during extraction.

### Decision: Treat uncertainty as unsafe

Archive entries SHALL be rejected if the extractor cannot prove that they are safe. This includes unparseable metadata, unknown entry types, unsupported special files, absolute paths, `..` traversal components, symlinks, hardlinks, and normalized paths that do not remain under the destination root.

Rationale:

- Archive import is a boundary for untrusted input.
- Partial extraction of an ambiguous archive creates unclear user-visible behavior.
- A conservative failure mode is easier to test and reason about.

### Decision: Validate sizes twice

The extractor SHALL enforce file count and declared uncompressed size limits before extraction. After extraction, it SHALL enumerate actual filesystem results and enforce root confinement, regular-file type, per-file size, and total regular-file size again.

Rationale:

- ZIP metadata is untrusted and must not be the only source of truth.
- Preflight limits reduce zip bomb risk before extraction.
- Post-extraction checks catch metadata/tool discrepancies and filesystem side effects.

### Decision: Preserve external error behavior while keeping internal errors precise

`ArchiveExtractor` MAY define precise internal errors such as path traversal, absolute path, unsupported entry type, too many files, single file too large, total size too large, unzip failure, and post-extraction validation failure. `FileInputService.extractArchive(_:)` SHALL map any extraction failure to `FileInputError.extractionFailed`.

Rationale:

- Tests can assert the extractor's precise rejection reasons.
- Existing UI and ViewModel error behavior do not change.
- The app does not expose detailed safety guard internals to archive authors.

### Decision: Log low-sensitivity diagnostic information only

`ArchiveExtractor` SHALL use `os.Logger` to log rejection categories, limit values, actual counts/sizes, and the archive `lastPathComponent`. Logs SHALL NOT include full absolute paths or full archive entry paths. If an entry hint is needed, it SHALL be sanitized and truncated to a basename.

Rationale:

- Developers need enough signal to diagnose import failures.
- Archive entry names are untrusted data and may contain private or adversarial content.
- Avoiding full paths reduces privacy and log-injection risk.

### Decision: Preserve `scanFolder` behavior exactly for valid archives

This change SHALL NOT alter `FileInputService.scanFolder(_:)` behavior. Valid archive imports still recurse through subfolders, skip `__MACOSX`, include `jpg`, `jpeg`, `png`, `gif`, `webp`, `bmp`, `tiff`, and `tif`, and sort using `lastPathComponent.localizedStandardCompare`.

Rationale:

- The change is a security fix, not an import behavior redesign.
- Users may already rely on current extension support and filename sorting.

## Risks / Trade-offs

- [Risk] System ZIP metadata output differs across macOS versions. → Mitigation: parse only fixed fields needed for safety, reject unparseable lines, and cover parser behavior with tests.
- [Risk] A valid but unusual archive is rejected because metadata is ambiguous. → Mitigation: conservative rejection is intentional for untrusted input; valid regular-file/directory archives remain supported.
- [Risk] Preflight limits may reject very large legitimate CBZ files. → Mitigation: limits are explicit and testable; they can be revised in a future change with user-facing size guidance if needed.
- [Risk] Logging accidentally records untrusted or private paths. → Mitigation: specify log content as categories, counts, sizes, limits, and archive basename only.
- [Risk] `FileInputService` cleanup misses a failure path. → Mitigation: tests SHALL cover failure cleanup for malicious and over-limit archives.
- [Risk] Future model download work accidentally expands this change. → Mitigation: the proposal, spec, and tasks explicitly keep `ModelDownloadService` out of scope.
