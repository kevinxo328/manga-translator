## ADDED Requirements

### Requirement: Benchmark suite includes targeted regression checks for known PaddleOCR empty cases
The OCR benchmark capability SHALL provide targeted regression validation for known PaddleOCR benchmark crops that previously produced empty or newline-only results in the production Swift runtime.

#### Scenario: Regression case remains covered
- **WHEN** the benchmark-oriented regression suite runs
- **THEN** it includes the known PaddleOCR empty-case crops as explicit validation targets

#### Scenario: Fixed runtime on known empty case
- **WHEN** the production Swift PaddleOCR path is executed on a known benchmark-empty crop after the runtime fix
- **THEN** the regression result records non-empty recognition behavior instead of an empty or newline-only output
