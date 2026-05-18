## ADDED Requirements

### Requirement: Low-confidence detection counter
For each image, the benchmark report SHALL record the number of detector outputs whose confidence falls in the band `[0.40, 0.60)`. This counter monitors the FP-risk margin around the current shared threshold so that a future corpus-diversification audit can detect drift without requiring a full visual re-audit.

#### Scenario: Page with no marginal detections
- **WHEN** every detection on a page has confidence at or above `0.60`
- **THEN** the report records `lowConfidenceDetections = 0` for that page

#### Scenario: Page with marginal detections
- **WHEN** a page produces detections at confidences `[0.95, 0.91, 0.45, 0.52]`
- **THEN** the report records `lowConfidenceDetections = 2` for that page

### Requirement: Inverted-bubble counter
For each image, the benchmark report SHALL record the number of `BubbleCluster` results whose `isInverted` flag is `true`. This counter validates that polarity detection (see `bubble-detection` spec) is firing on pages known to contain inverted bubbles.

#### Scenario: Page with only normal-polarity bubbles
- **WHEN** every detected bubble on a page has `isInverted == false`
- **THEN** the report records `invertedBubbles = 0` for that page

#### Scenario: Page with several inverted-polarity bubbles
- **WHEN** a page contains a mix of normal and inverted bubbles, and 3 of them are classified as inverted
- **THEN** the report records `invertedBubbles = 3` for that page
