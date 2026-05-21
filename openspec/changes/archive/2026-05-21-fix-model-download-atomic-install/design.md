## Context

`ModelDownloadService` currently treats `config.modelDirectory` as both the legacy install root and the active model directory. The download flow verifies the zip checksum, extracts to a staging directory under the active root, moves extracted top-level items into the active root, and then persists `UserDefaults` metadata.

That flow is not atomic. A failed extraction, non-zero `unzip` exit, validation failure, or move failure can leave a partially updated active directory. Because existing files may be removed before replacement files are fully installed, a user who already had a valid local model can lose high-accuracy OCR after a failed update.

The existing production install root is:

`~/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL/`

This change keeps that path as the legacy root and introduces a sibling active directory for new atomic installs:

`~/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL.current/`

## Goals / Non-Goals

**Goals:**

- Ensure failed download, checksum, extraction, validation, install, or rollback steps do not modify any previously usable model.
- Define exact model directory roles so implementation and tests do not infer paths differently.
- Keep existing legacy installs usable after upgrade.
- Make resolver behavior deterministic when both legacy and new active directories exist.
- Persist downloaded/checksum metadata only after a complete successful install.
- Clean temporary install artifacts after successful installs and handled failures.
- Cover app launch verification and deletion so `.current`, legacy root, staging, and backup paths do not diverge.

**Non-Goals:**

- Do not migrate or move a legacy `PaddleOCR-VL` directory before a successful new model install.
- Do not remove the legacy root as part of a successful `.current` install.
- Do not change model download URLs, checksum format, UI copy, or high-accuracy OCR routing policy.
- Do not introduce a new model manifest format.
- Do not make path resolution depend on modification times.

## Decisions

### Directory layout

Use `config.modelDirectory` as the legacy root only. Its parent directory is the model container:

- Legacy root: `<models>/PaddleOCR-VL`
- Active current: `<models>/PaddleOCR-VL.current`
- Installing root: `<models>/.installing`
- Next candidate: `<models>/.installing/PaddleOCR-VL.next.<uuid>`
- Backup current: `<models>/PaddleOCR-VL.backup.<uuid>`

Rationale: sibling directories allow the service to replace `.current` without touching the legacy root. They also prevent staging cleanup from deleting legacy model contents.

Alternative considered: place `.current`, `.installing`, and backup under `PaddleOCR-VL/`. This was rejected because cleanup and replacement operations would be too close to the legacy active data and could still delete user-owned usable model files on failure.

### Install transaction

The install transaction has four phases:

1. Download the archive to a temporary file outside the active model directory.
2. Verify the archive SHA256 against the configured checksum.
3. Create a unique `.next` directory under `.installing`, copy or move the verified archive to `.next/model.zip`, and extract archive contents only into `.next`.
4. Validate `.next` model structure, then swap `.next` into `.current`.

The service MUST NOT rename, delete, or overwrite `.current` until `.next` passes all validation.

Rationale: the current model remains untouched until the replacement is known to be usable.

### Swap and rollback

If `.current` exists, the service renames `.current` to a unique backup path, then renames `.next` to `.current`. After the `.current` rename succeeds, the backup is deleted.

If `.current` does not exist, the service renames `.next` directly to `.current`.

If any step after `.current` is renamed to backup fails, the service attempts to restore the backup to `.current`. Rollback failure is logged with `DebugLogger`. The legacy root is never modified by this rollback flow.

Rationale: rollback gives the prior `.current` a best-effort recovery path without making legacy compatibility part of the transaction.

### Failure state rules

At the start of an install attempt, record whether a valid model resolves and whether high-accuracy OCR is enabled. If the attempt fails and a prior valid model existed, restore the prior downloaded state: keep existing downloaded/checksum metadata, keep the enabled preference, and return `ModelDownloadState` to `.downloaded`. If the attempt fails and no valid model existed before the attempt, clear downloaded/checksum metadata, set `paddleocr.enabled = false`, and transition to `.failed`.

Rationale: users who already had a usable model should keep using it after an update failure. First-install failures still surface as `.failed` because there is no usable prior model to select.

### Resolver priority

`resolvedModelDirectory` MUST resolve model directories in this exact priority:

1. `<models>/PaddleOCR-VL.current`
2. `<models>/PaddleOCR-VL`
3. The single valid model child under `<models>/PaddleOCR-VL`

Each candidate is valid only if it satisfies the existing supported-model-weights predicate. If no candidate is valid, or if legacy child resolution finds more than one valid child, resolution fails.

Rationale: successful new installs are preferred, existing legacy installs still work, and ambiguous legacy child layouts do not route inference unpredictably.

### Validation scope

This change keeps the existing minimum model structure validation predicate: a valid model directory contains `weights.npz` or `model.safetensors`. The implementation may reuse `hasSupportedModelWeights`.

Rationale: Task 4 is about atomicity and failure handling. Expanding the required model manifest would be a separate compatibility-sensitive change.

### Archive persistence

For new installs, the verified archive is stored at `<models>/PaddleOCR-VL.current/model.zip` after the swap. During staging it is stored at `<models>/.installing/PaddleOCR-VL.next.<uuid>/model.zip`.

Legacy installs continue to support `<models>/PaddleOCR-VL/model.zip`.

Rationale: launch verification can continue to compare the stored archive against persisted checksum without inventing new metadata.

### Metadata updates

`paddleocr.model.downloaded`, `paddleocr.model.checksum`, `paddleocr.model.lastVerified`, and `paddleocr.enabled` are updated only after `.current` exists and resolves as a valid model directory. Failure paths leave existing persisted downloaded/checksum metadata unchanged when a prior valid model remains usable.

Rationale: metadata must describe a usable model, not a partially completed operation.

### Extraction

Extraction MUST fail when `/usr/bin/unzip` exits with any non-zero status. The extractor MUST also reject entries whose resolved paths escape the staging candidate directory.

Rationale: non-zero process exit indicates incomplete extraction, and path traversal can otherwise write outside the intended install area.

## Risks / Trade-offs

- [Risk] A failed rollback after `.current` was moved to backup could leave `.current` missing. -> Mitigation: log rollback failure, keep legacy root untouched, return to `.downloaded` only if another valid model still resolves, otherwise return `.failed`, and require tests for rollback behavior.
- [Risk] Keeping legacy root after successful `.current` install uses extra disk space. -> Mitigation: this is intentional for compatibility; cleanup of legacy data can be specified separately.
- [Risk] Existing deletion behavior may remove only legacy root and leave `.current`. -> Mitigation: update delete requirements and tasks to delete `.current`, legacy root, `.installing`, and backup artifacts.
- [Risk] Launch verification may check the wrong archive path. -> Mitigation: resolver and archive path lookup must use the same priority as active directory resolution.
- [Risk] Tests that use flat fake files may not represent valid model structure. -> Mitigation: new tests must create a minimal valid model directory containing `weights.npz` or `model.safetensors`.

## Migration Plan

1. Leave existing `PaddleOCR-VL` legacy installs in place.
2. On first successful new download/update, install the model into `PaddleOCR-VL.current`.
3. After `.current` exists and validates, resolver uses `.current` for future inference.
4. If installation fails at any point before `.current` is valid, continue resolving the legacy root if it is valid.
5. Do not delete legacy root during this change.

Rollback strategy: reverting this change leaves legacy root installs untouched. If `.current` exists after revert, older code that only knows `PaddleOCR-VL` may not use it; users can re-download under the older flow if necessary.

## Open Questions

None. Directory layout, resolver priority, validation scope, metadata timing, and cleanup responsibilities are intentionally fixed by this change.
