## MODIFIED Requirements

### Requirement: Run high-accuracy OCR inference on Apple Silicon
The system SHALL load the quantized MLX model from Application Support and run text recognition on cropped image regions. The recognizer SHALL conform to `OCRRecognizing`. The system SHALL lazy-load the model on first inference. The system SHALL expose deterministic unload/reset hooks for app-controlled lifecycle events and SHALL release in-memory model resources when those hooks are invoked. The system SHALL also release the model from memory when the system sends a memory pressure notification, and reload on next inference.

The high-accuracy PaddleOCR text runtime SHALL use a text-side rotary implementation that is compatible with the verified PaddleOCR-VL reference path. The runtime SHALL NOT rely on a text rotary path that causes the confirmed first-step parity failure on known benchmark crops.

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

#### Scenario: Known benchmark crop no longer terminates with first-step EOS
- **WHEN** the Swift high-accuracy OCR runtime processes a known regression crop that previously emitted first-step `EOS`
- **THEN** the runtime SHALL produce non-empty text generation behavior consistent with the verified reference path

#### Scenario: Known benchmark crop no longer terminates with first-step newline
- **WHEN** the Swift high-accuracy OCR runtime processes a known regression crop that previously emitted first-step newline-only output
- **THEN** the runtime SHALL produce text generation behavior instead of terminating with a newline-only result
