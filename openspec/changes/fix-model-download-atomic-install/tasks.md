## 1. Test Fixtures And Injection Points

- [ ] 1.1 Add test fixtures in `ModelDownloadServiceTests` for creating minimal valid model directories containing `weights.npz` or `model.safetensors`
- [ ] 1.2 Add test fixtures for model container layouts: current-only, legacy-root-only, legacy-single-child, legacy-multiple-children, and current-plus-legacy
- [ ] 1.3 Add a test seam for extraction so tests can simulate successful extraction, path traversal rejection, non-zero unzip exit, and thrown extraction errors without relying only on `/usr/bin/unzip`
- [ ] 1.4 Add a test seam for install file operations if needed to simulate active rename failure and rollback failure deterministically

## 2. Resolver Tests First

- [ ] 2.1 Add a failing test that resolver returns `<models>/PaddleOCR-VL.current` when both `.current` and legacy root are valid
- [ ] 2.2 Add a failing test that resolver returns legacy root when `.current` is absent and legacy root is valid
- [ ] 2.3 Add a failing test that resolver returns the single valid legacy child when `.current` is absent and legacy root itself is not valid
- [ ] 2.4 Add a failing test that resolver returns no model when legacy root has multiple valid children and no valid `.current` or valid legacy root
- [ ] 2.5 Add a failing test that resolver falls back to valid legacy root when `.current` exists but lacks supported model weights

## 3. Resolver Implementation

- [ ] 3.1 Add helpers that derive the model container parent from `config.modelDirectory`
- [ ] 3.2 Update `resolvedModelDirectory` or add an overload so production resolution checks `.current`, legacy root, then legacy single child in the required order
- [ ] 3.3 Keep `hasSupportedModelWeights` as the validation predicate for Task 4
- [ ] 3.4 Ensure production model search roots continue to cover default and sandbox container locations without changing unrelated routing behavior

## 4. Atomic Install Failure Tests First

- [ ] 4.1 Add a failing test that failed extraction preserves an existing valid `.current` model, resolver still returns it, metadata remains unchanged, and state returns to `.downloaded`
- [ ] 4.2 Add a failing test that failed extraction preserves an existing valid legacy root model, resolver still returns it, metadata remains unchanged, and state returns to `.downloaded`
- [ ] 4.3 Add a failing test that first-install non-zero unzip exit clears `paddleocr.model.downloaded` and `paddleocr.model.checksum`, disables `paddleocr.enabled`, and transitions state to `.failed`
- [ ] 4.4 Add a failing test that path traversal during extraction deletes the current attempt staging directory and follows deterministic failure state rules for prior-model versus first-install cases
- [ ] 4.5 Add a failing test that checksum mismatch deletes only the current attempt archive/staging and preserves prior valid `.current` or legacy model directories
- [ ] 4.6 Add a failing test that extracted contents without supported model weights are not promoted to `.current`
- [ ] 4.7 Add a failing test that install rename failure preserves or restores the previous `.current`, leaves metadata unchanged, and returns state to `.downloaded` when a prior valid model existed
- [ ] 4.8 Add a failing test that rollback failure logs through debug logging, leaves legacy root untouched, does not mark the failed attempt downloaded, and follows deterministic failure state rules
- [ ] 4.9 Add a failing test that cancelling an update with a prior valid model returns state to `.downloaded` and cancelling a first install returns state to `.notDownloaded`

## 5. Atomic Install Implementation

- [ ] 5.1 Refactor download flow so downloaded archive checksum is verified before any extraction directory is created
- [ ] 5.2 Capture pre-attempt resolved model, downloaded/checksum metadata, and enabled preference before mutating install artifacts
- [ ] 5.3 Create each install candidate at `<models>/.installing/PaddleOCR-VL.next.<uuid>`
- [ ] 5.4 Store the verified archive at `<models>/.installing/PaddleOCR-VL.next.<uuid>/model.zip` before extraction completes
- [ ] 5.5 Extract archive contents only into the `.next` candidate and reject any extracted path outside that candidate
- [ ] 5.6 Treat every non-zero `/usr/bin/unzip` termination status as extraction failure
- [ ] 5.7 Validate the `.next` candidate with `hasSupportedModelWeights` before changing `.current`
- [ ] 5.8 Promote valid `.next` to `.current`; when `.current` already exists, rename it to a unique backup before promotion
- [ ] 5.9 Delete the backup only after the new `.current` promotion succeeds
- [ ] 5.10 On post-backup failure, attempt rollback from backup to `.current`; if rollback fails, write a debug log and apply deterministic failure state rules
- [ ] 5.11 Preserve legacy `PaddleOCR-VL` during every install path, including successful `.current` installs
- [ ] 5.12 Update `UserDefaults` downloaded/checksum/lastVerified and `paddleocr.enabled` only after `.current` resolves as valid
- [ ] 5.13 On failed attempts, restore prior downloaded state when a valid pre-attempt model existed; otherwise clear download metadata, disable `paddleocr.enabled`, and set state to `.failed`

## 6. Cleanup Tests First

- [ ] 6.1 Add a failing test that successful install leaves no `.installing/PaddleOCR-VL.next.<uuid>` directory and no backup directory from the completed attempt
- [ ] 6.2 Add a failing test that path traversal failure leaves no staging candidate from the failed attempt
- [ ] 6.3 Add a failing test that non-zero unzip exit leaves no staging candidate from the failed attempt
- [ ] 6.4 Add a failing test that validation failure leaves no staging candidate from the failed attempt
- [ ] 6.5 Add a failing test that cleanup never removes a valid legacy `PaddleOCR-VL` directory

## 7. Cleanup Implementation

- [ ] 7.1 Centralize cleanup for the current attempt's `.next` candidate and empty `.installing` directory
- [ ] 7.2 Ensure success cleanup removes only the backup created by the completed install
- [ ] 7.3 Ensure failure cleanup removes only artifacts created by the current attempt unless delete is explicitly invoked
- [ ] 7.4 Update cancellation cleanup so it removes current-attempt staging artifacts without deleting prior valid `.current` or legacy models

## 8. Launch Verification Tests First

- [ ] 8.1 Add a failing test that launch verification accepts valid `.current/model.zip` with matching stored checksum
- [ ] 8.2 Add a failing test that launch verification accepts valid legacy `PaddleOCR-VL/model.zip` when `.current` is absent
- [ ] 8.3 Add a failing test that launch verification resets downloaded state when no valid model directory resolves
- [ ] 8.4 Add a failing test that launch verification resets downloaded state when resolved directory lacks `model.zip`
- [ ] 8.5 Add a failing test that launch verification resets downloaded state when resolved archive checksum mismatches stored checksum

## 9. Launch Verification Implementation

- [ ] 9.1 Update `verifyOnLaunch()` to resolve the active model directory before choosing the archive path
- [ ] 9.2 Verify `<resolvedModelDirectory>/model.zip` against stored checksum
- [ ] 9.3 Clear downloaded/checksum/lastVerified and disable `paddleocr.enabled` when resolution or archive verification fails
- [ ] 9.4 Keep launch verification asynchronous and preserve the existing fresh-evidence fast path only when the resolved directory and archive path are valid

## 10. Delete Tests First

- [ ] 10.1 Add a failing test that `delete()` removes `PaddleOCR-VL.current`
- [ ] 10.2 Add a failing test that `delete()` removes legacy `PaddleOCR-VL`
- [ ] 10.3 Add a failing test that `delete()` removes `.installing` and `PaddleOCR-VL.backup.<uuid>` artifacts
- [ ] 10.4 Add a failing test that `delete()` succeeds silently when no current, legacy, staging, or backup artifacts exist
- [ ] 10.5 Add a failing test that `delete()` clears downloaded/checksum/lastVerified, disables `paddleocr.enabled`, and sets state to `.notDownloaded`

## 11. Delete Implementation

- [ ] 11.1 Update `delete()` to remove `.current`, legacy root, `.installing`, and matching backup directories under the model container
- [ ] 11.2 Preserve existing inference coordination so delete waits for active inference before removing model artifacts
- [ ] 11.3 Keep delete idempotent when any target path is already absent
- [ ] 11.4 Preserve deterministic final state when delete overlaps launch verification

## 12. Verification

- [ ] 12.1 Run `xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -only-testing:MangaTranslatorTests/ModelDownloadServiceTests`
- [ ] 12.2 Confirm all new tests fail before their implementation changes and pass after implementation
- [ ] 12.3 Run any broader affected tests if shared extraction code or lifecycle coordination code is changed
- [ ] 12.4 Confirm no successful or handled failure path leaves `.installing`, `.next`, or backup directories behind
- [ ] 12.5 Confirm no failure path modifies or deletes a previously valid `.current` or legacy model directory
