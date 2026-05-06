## Purpose

Regression validation for Swift PaddleOCR runtime parity on known benchmark crops, with targeted test coverage that preserves production-path confidence without requiring a permanent production debug surface.

## Requirements

### Requirement: Validate PaddleOCR crop-level runtime parity on known regression crops
The system SHALL provide regression validation for Swift PaddleOCR runtime parity on known benchmark regression crops. The validation SHALL exercise the production Swift PaddleOCR runtime on fixed crops and compare its first-step behavior against the verified reference expectation for those same crops.

#### Scenario: Known benchmark-empty punctuation crop
- **WHEN** the regression suite runs against a known punctuation crop that previously produced an empty result in the Swift runtime
- **THEN** the Swift runtime SHALL emit a non-empty first-step text token instead of terminating with `EOS` or newline

#### Scenario: Known benchmark-empty dialogue crop
- **WHEN** the regression suite runs against a known dialogue crop that previously produced an empty result in the Swift runtime
- **THEN** the Swift runtime SHALL emit a first-step token consistent with real text generation instead of terminating immediately

### Requirement: Preserve targeted parity validation without production-only debug surface
The system SHALL retain regression validation for the known runtime-parity failures without requiring permanent production-facing tensor export hooks.

#### Scenario: Post-fix regression suite
- **WHEN** the fix is complete and investigation-only hooks are removed or restricted
- **THEN** the regression suite SHALL still validate the known benchmark-empty cases through stable test-only or debug-only entry points
