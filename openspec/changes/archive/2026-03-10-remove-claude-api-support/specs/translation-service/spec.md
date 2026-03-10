## REMOVED Requirements

### Requirement: Support Claude LLM translation backend
**Reason**: Claude API integration is being removed to simplify the service architecture and focus on DeepL, Google, and OpenAI Compatible providers.
**Migration**: Users should switch to the OpenAI Compatible engine or other supported services.

#### Scenario: Claude translates with stable index contract
- **WHEN** user selects Claude engine and translates a page
- **THEN** all bubbles are sent with their original indices, Claude returns JSON echoing back the same indices

#### Scenario: Claude respects active glossary
- **WHEN** an active glossary contains the term "炭治郎 → 炭治郎" and user translates a page containing "炭治 郎"
- **THEN** the translated output uses "炭治郎" consistently, not an alternative rendering

#### Scenario: Claude auto-detects new proper nouns
- **WHEN** Claude identifies a new proper noun not in the active glossary
- **THEN** the response includes it in `detected_terms` and the system writes it to the active glossary as auto-detected

#### Scenario: Claude index echoed back unchanged
- **WHEN** bubbles with indices [0, 2, 3] are sent (after punctuation filtering)
- **THEN** the response contains exactly indices [0, 2, 3], not [0, 1, 2]
