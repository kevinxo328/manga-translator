## MODIFIED Requirements

### Requirement: Support Claude LLM translation backend
The system SHALL support Anthropic Claude API as a translation backend, following the same whole-page context approach as OpenAI. The LLM prompt SHALL additionally include: (1) active glossary terms under a "## Glossary" section with the instruction that the LLM MUST follow them exactly, and (2) recent translated pages under a "## Recent context" section when available. The LLM response JSON format is extended to include an optional `detected_terms` array: `[{"index": 0, "translation": "...", "detected_terms": [{"source": "...", "target": "..."}]}]`. The system SHALL extract `detected_terms` from the first bubble's response entry (or aggregate across all) and write new terms to the active glossary.

#### Scenario: Claude translates with reading order correction
- **WHEN** user selects Claude engine and translates a page
- **THEN** all bubbles are sent with positions, Claude returns JSON with translations and optionally corrected reading order

#### Scenario: Claude respects active glossary
- **WHEN** an active glossary contains the term "炭治郎 → 炭治郎" and user translates a page containing "炭治郎"
- **THEN** the translated output uses "炭治郎" consistently, not an alternative rendering

#### Scenario: Claude auto-detects new proper nouns
- **WHEN** Claude identifies a new proper noun not in the active glossary
- **THEN** the response includes it in `detected_terms` and the system writes it to the active glossary as auto-detected

### Requirement: Support OpenAI LLM translation backend
The system SHALL support OpenAI API (GPT models) as a translation backend. The system SHALL send all bubbles on a page in a single request with positional context and a system prompt instructing manga-style translation. The system prompt SHALL additionally include glossary terms and recent page context using the same structure as the Claude backend. The response SHALL be in JSON format with the extended `detected_terms` field.

#### Scenario: OpenAI translates full page with context
- **WHEN** user selects OpenAI engine and translates a page with 5 bubbles
- **THEN** all 5 bubbles are sent in one API call with position data, and a JSON array of translations is returned

#### Scenario: OpenAI respects active glossary
- **WHEN** an active glossary is set and user translates with OpenAI engine
- **THEN** the system prompt includes the glossary terms and the response honours them
