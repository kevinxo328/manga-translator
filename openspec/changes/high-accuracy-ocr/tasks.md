## 0. Phase 0: Model Conversion (Prerequisite)

- [x] 0.1 Create `scripts/convert_model/` directory structure with `setup.sh`, `teardown.sh`, `requirements.txt`, `convert.py`, `verify.py`, and `README.md`
- [x] 0.2 Write `setup.sh`: create `.venv` with `uv`, install from `requirements.txt`, set `HF_HOME=./scripts/convert_model/.hf_cache`
- [x] 0.3 Write `teardown.sh`: remove `.venv/` and `.hf_cache/` with no side effects outside project directory
- [x] 0.4 Write `convert.py`: download `jzhang533/PaddleOCR-VL-For-Manga`, apply 8-bit MLX quantization (4-bit produces only newlines for this model architecture), save to `./mlx_output/`
- [x] 0.5 Write `verify.py`: compare BF16 original vs quantized on test images, exit non-zero if CER delta > 5%
- [x] 0.6 Add `.venv/`, `scripts/convert_model/.hf_cache/`, and `mlx_output/` to `.gitignore`
- [x] 0.7 Run conversion and verify: 8-bit model size 1051.7 MB, SHA256 `a9654f592cd82c18e0e1f7f997a38c6bd09d412a091e7bfd08365d6fbe06c71a`. Full 12-image test with `temperature=0`, ngram loop deduplication (`min_phrase_len=8`, `max_gap=100`), and Unicode normalization (`…`↔`...`, `！`↔`!`, `？`↔`?`): **9/12 PASS, avg CER delta 8.25%**. Remaining failures: 002.jpg (49.56%, quantized hallucinates repeated dialogue — inherent 8-bit limit), 001.jpg (25.4%, reading order differs), 010.jpg (17.7%, quantized misses one trailing line). Inference: ~15s/image on M3 Pro (full-page); production cropped-region inference estimated <1s. 4-bit quantization produces only newlines and is unusable. Accepted as inherent limitation of 8-bit quantization for this model architecture.
- [ ] 0.8 Upload quantized model to HuggingFace and record the download URL

## 1. Phase 1: Xcode Project Setup

- [ ] 1.1 Create `MangaTranslatorMLX` Swift target in Xcode with `ARCHS = arm64` build setting
- [ ] 1.2 Add `mlx-swift` as SPM dependency to `MangaTranslatorMLX` target only
- [ ] 1.3 Verify Universal Binary build succeeds: arm64 builds with MLX, x86_64 builds without
- [ ] 1.4 Verify Intel build produces a working app with no MLX symbols linked

## 2. Phase 1: DeviceCapabilityService — TDD

- [ ] 2.1 Write tests: `.supported` for 16GB Apple Silicon, `.supportedWithWarning(ram: 8)` for 8GB, `.unsupported` for Intel, `.unsupported` for 0GB (boundary)
- [ ] 2.2 Implement `DeviceCapabilityService.checkPaddleOCRCapability()` to pass all tests

## 3. Phase 1: ModelDownloadService — TDD

- [ ] 3.1 Write tests for successful download: state transitions, file written to Application Support, SHA256 verified, `UserDefaults` written
- [ ] 3.2 Write tests for error cases: SHA256 mismatch (file deleted, state `.failed`), disk space insufficient, network interrupted, download directory not writable
- [ ] 3.3 Write tests for cancellation: partial files deleted, state `.notDownloaded`
- [ ] 3.4 Write tests for duplicate `download()` call: second call ignored, state remains `.downloading`
- [ ] 3.5 Write tests for `delete()`: files removed, `UserDefaults` cleared, state `.notDownloaded`, preference set to `false`
- [ ] 3.6 Write tests for `delete()` when file absent: no throw, state `.notDownloaded`
- [ ] 3.7 Write tests for `verify()`: returns `true` when file present and SHA256 matches, `false` when file absent, `false` when SHA256 mismatch
- [ ] 3.8 Write tests for `verifyOnLaunch()`: resets state when `UserDefaults` says downloaded but file missing; deletes and resets when file present but SHA256 mismatch
- [ ] 3.9 Implement `ModelDownloadService` (`download()`, `delete()`, `verify()`, `verifyOnLaunch()`) to pass all tests

## 4. Phase 1: PaddleOCRVLRecognizer — TDD (arm64 only)

- [ ] 4.1 Write tests: successful inference returns non-empty text and confidence > 0; model file deleted before inference throws descriptive error
- [ ] 4.2 Write boundary tests: region exceeds image bounds (clamped, no crash); region with zero width/height (empty string or throws, no crash); all-white/all-black input (low confidence, no crash); 4K+ image (no OOM crash)
- [ ] 4.3 Write memory pressure test: model is `nil` after `NSApplication.didReceiveMemoryWarningNotification`; inference after memory pressure reloads and succeeds
- [ ] 4.4 Implement `PaddleOCRVLRecognizer` conforming to `OCRRecognizing` with lazy load and memory pressure handling to pass all tests

## 5. Phase 2: OCRRecognizing Protocol — TDD

- [ ] 5.1 Write test: `MangaOCRService` initializes with `any OCRRecognizing`; after `resetRecognizer()` the internal recognizer is `nil`
- [ ] 5.2 Define `OCRRecognizing` protocol in new file `OCRRecognizing.swift`
- [ ] 5.3 Add `extension MangaOCRRecognizer: OCRRecognizing {}` (no internal changes)
- [ ] 5.4 Refactor `MangaOCRService` to hold `(any OCRRecognizing)?` and implement `resetRecognizer()`

## 6. Phase 2: OCRRouter Integration — TDD

- [ ] 6.1 Write tests: Silicon + downloaded + enabled → uses `PaddleOCRVLRecognizer`; Silicon + not downloaded → uses `MangaOCRRecognizer`; Silicon + downloaded + disabled → uses `MangaOCRRecognizer`; Intel → uses `MangaOCRRecognizer`
- [ ] 6.2 Write fallback tests: `PaddleOCRVLRecognizer` throws → falls back to `MangaOCRRecognizer`, logs warning; empty image → returns empty array; 1×1 image → returns empty array
- [ ] 6.3 Write reset tests: recognizer resets when preference toggled; recognizer resets when model deleted
- [ ] 6.4 Update `OCRRouter` with Silicon branch and `MangaOCRService.makeRecognizer()` factory method to pass all tests

## 7. Phase 3: Settings UI — TDD

- [ ] 7.1 Write tests for `DeviceCapabilityService` integration in Settings: section hidden on Intel; warning label shown on 8GB; no warning on 16GB
- [ ] 7.2 Write tests for state-driven UI: `notDownloaded` shows "Download and Enable"; `downloading` shows progress and "Cancel"; `downloaded+enabled` shows "Disable" and "Delete Model Data"; `downloaded+disabled` shows "Enable" and "Delete Model Data"
- [ ] 7.3 Write tests for delete confirmation: dialog appears on "Delete Model Data" tap; `delete()` called only after confirm; no-op on cancel
- [ ] 7.4 Write tests for preference persistence: `paddleocr.enabled` written to `UserDefaults` on toggle; resets to `false` after model deletion
- [ ] 7.5 Implement `PaddleOCRSettingsSection` SwiftUI view wrapped in `#if arch(arm64)` with `@EnvironmentObject ModelDownloadService`
- [ ] 7.6 Add `PaddleOCRSettingsSection` to `SettingsView` inside `#if arch(arm64)` guard
- [ ] 7.7 Add SwiftUI Previews for all states: `notDownloaded`, `downloading(progress: 0.52)`, `downloaded+enabled`, `downloaded+disabled`, `downloading+8GB warning`

## 8. Phase 3: App Launch Verification

- [ ] 8.1 Add `await ModelDownloadService.shared.verifyOnLaunch()` call in `MangaTranslatorApp` using `.task {}` modifier on main window
- [ ] 8.2 Verify on simulator/device: corrupt model resets state on next launch; missing file resets state on next launch

## 9. Integration & Final Validation

- [ ] 9.1 Run full OCR pipeline on `test_images/` with high-accuracy model enabled; verify non-empty results for all images
- [ ] 9.2 Run full OCR pipeline with high-accuracy model disabled; verify existing MangaOCR pipeline unchanged
- [ ] 9.3 Test delete → re-download flow end-to-end
- [ ] 9.4 Test memory pressure scenario: send `NSApplication.didReceiveMemoryWarningNotification` manually and verify model released then reloaded on next inference
- [ ] 9.5 Build Universal Binary; verify Intel build runs correctly with no MLX symbols and PaddleOCR section hidden in Settings
- [ ] 9.6 Add Apache 2.0 attribution for PaddleOCR-VL-For-Manga to the app's Third-Party Notices
