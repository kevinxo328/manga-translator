## MODIFIED Requirements

### Requirement: Support OpenAI LLM translation backend
The system SHALL support OpenAI API (GPT models) as a translation backend. The system SHALL send all bubbles on a page in a single request with positional context and a system prompt instructing manga-style translation. The user prompt SHALL use each bubble's original `bubble.index` (not enumeration offset) as the `index` field. The system prompt SHALL instruct the LLM to echo back the `index` field exactly as given without reordering. The system prompt SHALL additionally include glossary terms and recent page context using the same structure as the Claude backend. The response SHALL be in JSON format with the extended `detected_terms` field.

#### Scenario: OpenAI translates full page with context
- **WHEN** user selects OpenAI engine and translates a page with 5 bubbles
- **THEN** all 5 bubbles are sent in one API call with position data, and a JSON array of translations is returned with the same indices as received

#### Scenario: OpenAI respects active glossary
- **WHEN** an active glossary is set and user translates with OpenAI engine
- **THEN** the system prompt includes the glossary terms and the response honours them

#### Scenario: OpenAI index echoed back unchanged
- **WHEN** bubbles with indices [0, 2, 3] are sent (after punctuation filtering)
- **THEN** the response contains exactly indices [0, 2, 3], not [0, 1, 2]

### Requirement: Support Claude LLM translation backend
The system SHALL support Anthropic Claude API as a translation backend, following the same whole-page context approach as OpenAI. The user prompt SHALL use each bubble's original `bubble.index` (not enumeration offset) as the `index` field. The system prompt SHALL instruct the LLM to echo back the `index` field exactly as given without reordering. The LLM prompt SHALL additionally include: (1) active glossary terms under a "## Glossary" section with the instruction that the LLM MUST follow them exactly, and (2) recent translated pages under a "## Recent context" section when available. The LLM response JSON format is extended to include an optional `detected_terms` array: `[{"index": 0, "translation": "...", "detected_terms": [{"source": "...", "target": "..."}]}]`. The system SHALL extract `detected_terms` from the first bubble's response entry (or aggregate across all) and write new terms to the active glossary.

#### Scenario: Claude translates with stable index contract
- **WHEN** user selects Claude engine and translates a page
- **THEN** all bubbles are sent with their original indices, Claude returns JSON echoing back the same indices

#### Scenario: Claude respects active glossary
- **WHEN** an active glossary contains the term "炭治郎 → 炭治郎" and user translates a page containing "炭治郎"
- **THEN** the translated output uses "炭治郎" consistently, not an alternative rendering

#### Scenario: Claude auto-detects new proper nouns
- **WHEN** Claude identifies a new proper noun not in the active glossary
- **THEN** the response includes it in `detected_terms` and the system writes it to the active glossary as auto-detected

#### Scenario: Claude index echoed back unchanged
- **WHEN** bubbles with indices [0, 2, 3] are sent (after punctuation filtering)
- **THEN** the response contains exactly indices [0, 2, 3], not [0, 1, 2]

### Requirement: LLM JSON response parsing with retry
The system SHALL parse LLM translation responses as JSON arrays. The parser SHALL use a dictionary keyed by `bubble.index` to match response items to original bubbles, rather than using the index as a direct array offset. If parsing fails, the system SHALL retry the request up to 2 times. If all retries fail, the system SHALL fall back to line-by-line text parsing.

#### Scenario: Malformed JSON response
- **WHEN** the LLM returns invalid JSON on first attempt
- **THEN** the system retries, and if the retry returns valid JSON, uses that result

#### Scenario: All retries fail
- **WHEN** the LLM returns invalid JSON on all 3 attempts
- **THEN** the system falls back to splitting the response by newlines and matching to bubbles by position

#### Scenario: Parser uses dictionary lookup
- **WHEN** LLM returns an index value that was in the original request
- **THEN** the parser maps it to the correct bubble using dictionary lookup, not array indexing

#### Scenario: Parser ignores unknown indices
- **WHEN** LLM returns an index value not present in the original request
- **THEN** the parser silently drops that item and continues processing remaining items
