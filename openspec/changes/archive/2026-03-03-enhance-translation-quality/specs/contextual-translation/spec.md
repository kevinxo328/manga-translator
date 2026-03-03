## ADDED Requirements

### Requirement: Rolling recent-page context window
The system SHALL maintain an in-memory rolling window of the last 3 translated pages' text (concatenated translated bubble text per page, ordered by reading index). This window is session-only and cleared when the app is restarted or a new image set is loaded.

#### Scenario: Context window accumulates across pages
- **WHEN** user translates pages 1, 2, and 3 in sequence
- **THEN** translating page 4 includes a summary of pages 1–3 in the LLM prompt

#### Scenario: Context window drops oldest page
- **WHEN** user has translated 4 or more pages
- **THEN** only the most recent 3 pages are included in the context window

#### Scenario: Context clears on new image set
- **WHEN** user opens a different folder or file
- **THEN** the rolling context window is reset to empty

### Requirement: Recent context injected into LLM prompt
The system SHALL include the rolling context window in the LLM system prompt when context is available. The context SHALL be presented as a brief per-page summary under a "## Recent context" section. Only LLM-based engines (Claude, OpenAI) SHALL receive context injection; DeepL and Google are unaffected.

#### Scenario: LLM receives prior page context
- **WHEN** user translates a page and prior translated pages exist in the window
- **THEN** the LLM system prompt includes those pages' translations under "## Recent context (previous pages)"

#### Scenario: First page translation has no context
- **WHEN** user translates the first page of a session
- **THEN** no "## Recent context" section is included in the prompt
