## Why

Model download currently extracts archives into a staging directory and then moves top-level extracted items into the active model destination. If extraction, validation, or final moves fail, the operation can delete or overwrite files from an existing valid local model, leaving users without high-accuracy OCR even though they already had a usable model.

This change makes local model installation atomic and failure-safe so every failed download, extraction, validation, or install attempt preserves the previously usable model and leaves no ambiguous partially installed state.

## What Changes

- Replace in-place model extraction/install behavior with an explicit atomic install flow using sibling active, staging, and backup directories.
- Define the active model directory as `PaddleOCR-VL.current`, located beside the legacy `PaddleOCR-VL` root under `Application Support/MangaTranslator/Models/`.
- Extract and validate new model contents only inside `.installing/PaddleOCR-VL.next.<uuid>` before changing the active model.
- Swap `.next` to `.current` only after download checksum verification, archive extraction, and model structure validation all succeed.
- Preserve any existing valid `.current` model during failed downloads, failed extraction, failed validation, and failed install rollback.
- Preserve legacy `PaddleOCR-VL` installations during failed updates and use them as fallback when `.current` does not exist.
- Treat non-zero `/usr/bin/unzip` exit status as extraction failure.
- Clean staging, next, and backup directories after successful installs and after handled failures.
- Persist `UserDefaults` downloaded/checksum metadata only after a successful active-directory install.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-model-lifecycle`: Clarify and strengthen download/install requirements for atomic local model installation, extraction failure handling, active directory resolution, legacy fallback, metadata persistence, and cleanup.

## Impact

- Affected code:
  - `MangaTranslator/Services/ModelDownloadService.swift`
  - Possibly `MangaTranslator/Services/ArchiveExtractor.swift` if extraction is factored into a shared helper
  - `MangaTranslatorTests/ModelDownloadServiceTests.swift`
- Affected behavior:
  - Failed model updates no longer remove or corrupt the existing usable model.
  - Successful updates switch future inference to `PaddleOCR-VL.current`.
  - Existing legacy installs remain usable after app upgrade and after failed update attempts.
- No breaking user-facing API changes are expected.
