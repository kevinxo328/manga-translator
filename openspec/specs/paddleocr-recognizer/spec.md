## Purpose

Single owner for PaddleOCR-VL recognizer runtime behavior on Apple Silicon: model load from `local-model-lifecycle`-managed storage, OCR inference on detector-derived crops, lazy load and explicit unload/reset hooks, memory-pressure release with reload-on-next-inference, deterministic decode-loop and truncation termination, UI-responsive execution, baseline regression output preservation, input-boundary handling, and per-page MLX GPU buffer cache cleanup that preserves recognizer reuse.

## Requirements

### Requirement: Run PaddleOCR-VL recognition on Apple Silicon
The system SHALL load the quantized MLX model from Application Support and run text recognition on cropped image regions. The recognizer SHALL conform to `OCRRecognizing`. The system SHALL lazy-load the model on first inference. The system SHALL expose deterministic unload/reset hooks for app-controlled lifecycle events and SHALL release in-memory model resources when those hooks are invoked. The system SHALL also release the model from memory when the system sends a memory pressure notification, and reload on next inference.

The PaddleOCR text runtime SHALL use a text-side rotary implementation that is compatible with the verified PaddleOCR-VL reference path. The runtime SHALL NOT rely on a text rotary path that causes the confirmed first-step parity failure on known benchmark crops.

To preserve responsiveness, PaddleOCR inference MUST execute outside the UI-critical execution context while preserving strict-mode error semantics.

Any responsiveness optimization for this requirement MUST preserve baseline regression text output exactly for the approved high-accuracy OCR regression dataset.

#### Scenario: Successful inference on cropped region
- **WHEN** a cropped image region containing Japanese text is provided
- **THEN** the recognizer returns a result without crashing (text may be empty and confidence may be 0 for difficult inputs)

#### Scenario: Lazy load on first inference
- **WHEN** `recognizeText(in:region:)` is called for the first time
- **THEN** the model is loaded from Application Support before inference runs

#### Scenario: Memory pressure release
- **WHEN** the system sends `NSApplication.didReceiveMemoryWarningNotification`
- **THEN** the in-memory MLX model is released and the next inference reloads it before recognition

#### Scenario: Explicit unload hook
- **WHEN** app-controlled lifecycle events invoke recognizer unload/reset
- **THEN** in-memory MLX model resources are released deterministically even without a system memory warning notification

#### Scenario: Inference after explicit unload
- **WHEN** inference is requested after the model was released through an explicit unload/reset hook
- **THEN** the model is reloaded and inference succeeds

#### Scenario: Model file deleted externally before inference
- **WHEN** model files are deleted outside the app and `recognizeText` is called
- **THEN** a descriptive error is thrown

#### Scenario: Strict high-accuracy mode failure
- **WHEN** high-accuracy OCR is enabled and `PaddleOCRVLRecognizer` throws
- **THEN** the system surfaces a user-visible error and does not execute fallback recognizers

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

#### Scenario: UI remains responsive during high-accuracy inference
- **WHEN** high-accuracy OCR processes one or more regions for an in-progress page translation
- **THEN** OCR compute does not block the UI-critical execution context and the app remains responsive

#### Scenario: Baseline regression output parity is preserved
- **WHEN** the optimized high-accuracy OCR path runs on the approved regression dataset
- **THEN** recognized text output matches the pre-optimization baseline exactly

### Requirement: Stop unstable PaddleOCR decode output deterministically
The PaddleOCR runtime SHALL guard against repetitive decode loops and token-budget exhaustion that produce non-meaningful repeated output. The runtime SHALL stop generation when a loop or terminal truncation condition is detected and SHALL return the best available cleaned text for the crop.

#### Scenario: Repetitive phrase loop detected
- **WHEN** generated tokens enter a repeated phrase loop for a crop
- **THEN** generation stops before consuming the full decode budget and the recognizer returns the cleaned non-looping prefix

#### Scenario: Repeated punctuation loop detected
- **WHEN** generated tokens degrade into repeated punctuation or other low-information repetition
- **THEN** generation stops and the result is reported without the repeated tail

#### Scenario: Legitimate long crop output
- **WHEN** a crop contains a long but valid text sequence with no loop pattern
- **THEN** the runtime continues decoding until a normal stop condition or token limit is reached

#### Scenario: Token limit reached without loop detection
- **WHEN** generation reaches the configured token ceiling without EOS and without a detected loop
- **THEN** the runtime returns the truncated text deterministically and surfaces no silent crash

### Requirement: Clear MLX GPU buffer cache after PaddleOCR page processing
The system SHALL clear MLX GPU buffer cache after each production high-accuracy PaddleOCR page processing attempt completes. This cleanup SHALL run at the page boundary after PaddleOCR recognition finishes or fails. The cleanup SHALL NOT unload the cached PaddleOCR recognizer/model instance and SHALL NOT change the model's per-generation KV cache behavior.

#### Scenario: Successful PaddleOCR page clears GPU buffer cache
- **WHEN** the production PaddleOCR page path completes successfully
- **THEN** the system clears MLX GPU buffer cache once after the page attempt
- **THEN** the PaddleOCR recognizer/model instance remains reusable for a later page

#### Scenario: Failed PaddleOCR page clears GPU buffer cache
- **WHEN** the production PaddleOCR page path fails with a PaddleOCR error or unexpected OCR error
- **THEN** the system clears MLX GPU buffer cache once after the failed page attempt
- **THEN** the original OCR error remains the error surfaced to the caller

#### Scenario: Standard MangaOCR path does not clear PaddleOCR GPU cache
- **WHEN** the standard MangaOCR path processes a page without using PaddleOCR
- **THEN** the PaddleOCR MLX GPU buffer cache cleanup hook is not invoked

