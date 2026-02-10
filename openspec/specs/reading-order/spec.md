## Purpose

Sorting detected bubbles into manga reading order (right-to-left, top-to-bottom).

## Requirements

### Requirement: Sort bubbles by manga reading order
The system SHALL sort detected bubbles in manga reading order: right-to-left, top-to-bottom. Bubbles SHALL be partitioned into rows by vertical overlap, then each row sorted right-to-left by horizontal position.

#### Scenario: Simple grid layout
- **WHEN** four bubbles are detected at positions: top-left, top-right, bottom-left, bottom-right
- **THEN** the reading order is: top-right → top-left → bottom-right → bottom-left

#### Scenario: Bubbles at different heights
- **WHEN** bubble A is at (x:800, y:100) and bubble B is at (x:200, y:120), with overlapping Y ranges
- **THEN** they are in the same row, ordered A → B (right to left)

### Requirement: LLM-assisted order correction
When an LLM translation backend is active, the system SHALL include bubble positions in the translation prompt and request the LLM to reorder bubbles if the dialogue flow appears incorrect. The LLM response SHALL include the corrected reading order alongside translations.

#### Scenario: LLM corrects order based on dialogue semantics
- **WHEN** spatial ordering produces [bubble A: "Yes", bubble B: "Is that true?"] but B is a question that should precede A
- **THEN** the LLM reorders to [bubble B, bubble A] and translates in corrected order

#### Scenario: Non-LLM backend uses spatial order only
- **WHEN** the user selects DeepL as translation engine
- **THEN** only spatial heuristic ordering is applied, no LLM correction
