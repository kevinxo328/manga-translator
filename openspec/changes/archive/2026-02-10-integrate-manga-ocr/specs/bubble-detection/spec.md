## MODIFIED Requirements

### Requirement: Cluster text observations into speech bubbles
When using Vision OCR (non-Japanese languages), the system SHALL group spatially close text observations into bubble clusters using agglomerative clustering. Two text observations SHALL be merged into the same cluster when the distance between their nearest edges is less than 2x the median character height of the observations. When using manga-ocr pipeline (Japanese), text regions from comic-text-detector are already bubble-level regions, so no additional clustering is needed — each detected region becomes one BubbleCluster directly.

#### Scenario: Multiple lines in one bubble (Vision OCR path)
- **WHEN** using Vision OCR and a speech bubble contains 3 lines of text detected as 3 separate observations, all within 2x character height of each other
- **THEN** the system groups them into a single bubble cluster

#### Scenario: Manga-ocr detected regions
- **WHEN** using manga-ocr pipeline and comic-text-detector returns 5 text regions
- **THEN** the system creates 5 BubbleCluster objects directly, one per detected region, without additional clustering
