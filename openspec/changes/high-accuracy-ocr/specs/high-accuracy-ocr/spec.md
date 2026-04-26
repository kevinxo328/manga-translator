## ADDED Requirements

### Requirement: Detect device capability for high-accuracy OCR
The system SHALL detect whether the current device supports high-accuracy OCR. The system SHALL return `.supported` for Apple Silicon with ≥16GB RAM, `.supportedWithWarning(ram:)` for Apple Silicon with <16GB RAM, and `.unsupported` for Intel architecture or 0GB detected RAM.

#### Scenario: Apple Silicon with 16GB RAM
- **WHEN** the device is Apple Silicon with 16GB unified memory
- **THEN** `DeviceCapabilityService.checkPaddleOCRCapability()` returns `.supported`

#### Scenario: Apple Silicon with 8GB RAM
- **WHEN** the device is Apple Silicon with 8GB unified memory
- **THEN** `DeviceCapabilityService.checkPaddleOCRCapability()` returns `.supportedWithWarning(ram: 8)`

#### Scenario: Intel architecture
- **WHEN** the device is Intel architecture
- **THEN** `DeviceCapabilityService.checkPaddleOCRCapability()` returns `.unsupported`

#### Scenario: 0GB RAM detected (boundary)
- **WHEN** `ProcessInfo.physicalMemory` reports 0 bytes
- **THEN** `DeviceCapabilityService.checkPaddleOCRCapability()` returns `.unsupported`

---

### Requirement: Download high-accuracy OCR model on demand
The system SHALL allow Apple Silicon users to download the quantized OCR model from a configured HuggingFace URL to `~/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL/`. The system SHALL report download progress. The system SHALL verify the downloaded files using SHA256 checksum. The system SHALL persist download state and checksum in `UserDefaults`.

#### Scenario: Successful download
- **WHEN** user initiates download and the network request succeeds
- **THEN** model files are written to Application Support, SHA256 is verified, `UserDefaults` records `paddleocr.model.downloaded = true` and the checksum, and state transitions to `.downloaded`

#### Scenario: Download with progress reporting
- **WHEN** download is in progress
- **THEN** `ModelDownloadService.state` is `.downloading(progress:)` with a value between 0.0 and 1.0

#### Scenario: SHA256 checksum mismatch
- **WHEN** download completes but the file SHA256 does not match the expected value
- **THEN** the partial/corrupt file is deleted, `UserDefaults` keys are cleared, and state transitions to `.failed` with a descriptive error

#### Scenario: Disk space insufficient
- **WHEN** the download directory has insufficient disk space
- **THEN** state transitions to `.failed` with a descriptive error message

#### Scenario: Network interrupted during download
- **WHEN** the network connection drops during download
- **THEN** state transitions to `.failed` with an error; the operation can be retried

#### Scenario: Download cancelled by user
- **WHEN** user cancels an in-progress download
- **THEN** any partial files are deleted and state transitions to `.notDownloaded`

#### Scenario: Duplicate download call
- **WHEN** `download()` is called while state is already `.downloading`
- **THEN** the second call is ignored; state remains `.downloading`

#### Scenario: Download directory not writable
- **WHEN** the Application Support directory cannot be written to
- **THEN** state transitions to `.failed` with a descriptive error

---

### Requirement: Verify model integrity on app launch
The system SHALL verify model integrity on each app launch when `UserDefaults` indicates the model was previously downloaded. If the file is missing or the SHA256 does not match, the system SHALL reset state to `.notDownloaded` and clear `UserDefaults` keys.

#### Scenario: File present and valid on launch
- **WHEN** app launches and model file exists with matching SHA256
- **THEN** state is `.downloaded`

#### Scenario: UserDefaults shows downloaded but file missing
- **WHEN** app launches and `paddleocr.model.downloaded` is `true` but model file does not exist
- **THEN** state resets to `.notDownloaded` and `UserDefaults` keys are cleared

#### Scenario: File present but SHA256 mismatch on launch
- **WHEN** app launches and model file exists but SHA256 does not match stored value
- **THEN** corrupt file is deleted, state resets to `.notDownloaded`, and `UserDefaults` keys are cleared

---

### Requirement: Delete high-accuracy OCR model
The system SHALL allow users to delete the downloaded model, freeing disk space. Deletion SHALL remove all files in the model directory, clear `UserDefaults` keys, disable the high-accuracy OCR preference, and transition state to `.notDownloaded`. If no file exists, `delete()` SHALL succeed silently without throwing.

#### Scenario: Delete existing model
- **WHEN** user confirms deletion and model files exist
- **THEN** all files under `Application Support/MangaTranslator/Models/PaddleOCR-VL/` are removed, `UserDefaults` keys are cleared, the high-accuracy OCR preference is set to `false`, and state becomes `.notDownloaded`

#### Scenario: Delete when file already absent
- **WHEN** `delete()` is called but model files do not exist
- **THEN** no error is thrown and state is `.notDownloaded`

#### Scenario: Delete while inference is in progress
- **WHEN** `delete()` is called while `PaddleOCRVLRecognizer` is actively running inference
- **THEN** deletion waits for the current inference to complete before removing files

---

### Requirement: Run high-accuracy OCR inference on Apple Silicon
The system SHALL load the quantized MLX model from Application Support and run text recognition on cropped image regions. The recognizer SHALL conform to `OCRRecognizing`. The system SHALL lazy-load the model on first inference. The system SHALL release the model from memory when the system sends a memory pressure notification, and reload on next inference.

#### Scenario: Successful inference on cropped region
- **WHEN** a cropped image region containing Japanese text is provided
- **THEN** the recognizer returns a non-empty text string and a confidence value > 0

#### Scenario: Lazy load on first inference
- **WHEN** `recognizeText(in:region:)` is called for the first time
- **THEN** the model is loaded from Application Support before inference runs

#### Scenario: Memory pressure release
- **WHEN** the system sends `NSApplication.didReceiveMemoryWarningNotification`
- **THEN** the in-memory MLX model is released (`model = nil`)

#### Scenario: Inference after memory pressure
- **WHEN** inference is requested after the model was released due to memory pressure
- **THEN** the model is reloaded and inference succeeds

#### Scenario: Model file deleted externally before inference
- **WHEN** model files are deleted outside the app and `recognizeText` is called
- **THEN** a descriptive error is thrown

#### Scenario: Region exceeds image bounds (boundary)
- **WHEN** the provided `region` CGRect extends beyond the CGImage bounds
- **THEN** the region is clamped to image bounds and inference runs without crashing

#### Scenario: Region with zero width or height (boundary)
- **WHEN** the provided `region` CGRect has width = 0 or height = 0
- **THEN** the recognizer returns an empty string or throws without crashing

#### Scenario: All-white or all-black input image (boundary)
- **WHEN** a blank image region is provided
- **THEN** the recognizer returns a result (possibly empty) with low confidence, without crashing

#### Scenario: Very large input image (boundary)
- **WHEN** a 4K+ resolution image is provided
- **THEN** inference completes without out-of-memory crash

---

### Requirement: Reproducible model conversion script
The repo SHALL include self-contained Python tooling at `scripts/convert_model/` that converts the original HuggingFace model to MLX format, supports quantization parameter sweeps, and benchmarks BF16 vs quantized behavior on both page-level and crop-level datasets. (4-bit quantization is unusable for this model architecture — it produces only newlines.) The environment SHALL use `uv` and store all downloads in `scripts/convert_model/.hf_cache/`. Running `teardown.sh` SHALL completely remove `.venv/` and `.hf_cache/`, leaving no artifacts outside the project directory.

#### Scenario: Setup and conversion
- **WHEN** a developer runs `setup.sh` followed by `convert.py`
- **THEN** a `.venv/` is created, dependencies are installed, the model is downloaded to `.hf_cache/`, quantized, and written to the requested output directory

#### Scenario: Sweep conversion parameters
- **WHEN** a developer runs the sweep tooling with multiple quantization group sizes
- **THEN** separate MLX outputs and a machine-readable summary report are produced for each tested configuration

#### Scenario: Teardown removes all artifacts
- **WHEN** a developer runs `teardown.sh`
- **THEN** `.venv/` and `.hf_cache/` are fully removed; no files remain in `~/.cache/huggingface/` or other system directories

#### Scenario: Verify quantization quality
- **WHEN** `verify.py` is run with original and quantized models and either page-level test images or a crop manifest
- **THEN** the script reports CER deltas plus aggregate metrics including average, median, p90, max, catastrophic failures, loop count, and empty outputs; the script exits non-zero if any sample exceeds the configured CER threshold

#### Scenario: Use crop-level parity as the primary phase0 gate
- **WHEN** developers review phase0 verification output
- **THEN** crop-level BF16 vs quantized parity on detector-like text regions is treated as the primary go/no-go signal, and page-level CER is treated as a secondary sanity-check metric for loops, truncation, and ordering regressions
