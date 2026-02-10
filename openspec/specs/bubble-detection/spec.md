## Purpose

Clustering text observations into speech bubble regions.

## Requirements

### Requirement: Cluster text observations into speech bubbles
The system SHALL group spatially close text observations into bubble clusters using agglomerative clustering. Two text observations SHALL be merged into the same cluster when the distance between their nearest edges is less than 2x the median character height of the observations.

#### Scenario: Multiple lines in one bubble
- **WHEN** a speech bubble contains 3 lines of text detected as 3 separate observations, all within 2x character height of each other
- **THEN** the system groups them into a single bubble cluster

#### Scenario: Two separate bubbles
- **WHEN** two speech bubbles are far apart on the page (distance > 2x character height)
- **THEN** the system produces two separate bubble clusters

### Requirement: Compute bubble bounding rect
The system SHALL compute each bubble's bounding rectangle as the union of all text observation bounding boxes within the cluster.

#### Scenario: Bounding rect calculation
- **WHEN** a bubble cluster contains 3 text observations
- **THEN** the bubble bounding rect is the smallest rectangle that contains all 3 observation rects

### Requirement: Concatenate bubble text
The system SHALL concatenate text from all observations within a bubble cluster in top-to-bottom order (by Y coordinate) to produce the full bubble text.

#### Scenario: Vertical text ordering
- **WHEN** a bubble contains observations at y=100 ("Hello") and y=130 ("world")
- **THEN** the concatenated bubble text is "Hello world"
