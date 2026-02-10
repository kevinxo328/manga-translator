## Purpose

Translation backends and protocol for converting detected manga text between languages.

## Requirements

### Requirement: Unified translation protocol
The system SHALL define a `TranslationService` protocol that all translation backends conform to. The protocol SHALL accept an array of bubble texts (with positions) and return an array of translations. All backends receive the full page context.

#### Scenario: Protocol conformance
- **WHEN** a new translation backend is added
- **THEN** it conforms to the `TranslationService` protocol and can be used interchangeably

### Requirement: Support DeepL translation backend
The system SHALL support DeepL API as a translation backend. DeepL SHALL translate each bubble independently via the DeepL REST API.

#### Scenario: DeepL translates Japanese to Traditional Chinese
- **WHEN** user selects DeepL engine and translates a page from Japanese to Traditional Chinese
- **THEN** each bubble is sent to DeepL API and the translated text is returned

### Requirement: Support Google Translate backend
The system SHALL support Google Cloud Translation API as a translation backend.

#### Scenario: Google translates English to Japanese
- **WHEN** user selects Google engine and translates a page from English to Japanese
- **THEN** each bubble is sent to Google Cloud Translation API and the translated text is returned

### Requirement: Support OpenAI LLM translation backend
The system SHALL support OpenAI API (GPT models) as a translation backend. The system SHALL send all bubbles on a page in a single request with positional context and a system prompt instructing manga-style translation. The response SHALL be in JSON format.

#### Scenario: OpenAI translates full page with context
- **WHEN** user selects OpenAI engine and translates a page with 5 bubbles
- **THEN** all 5 bubbles are sent in one API call with position data, and a JSON array of translations is returned

### Requirement: Support Claude LLM translation backend
The system SHALL support Anthropic Claude API as a translation backend, following the same whole-page context approach as OpenAI.

#### Scenario: Claude translates with reading order correction
- **WHEN** user selects Claude engine and translates a page
- **THEN** all bubbles are sent with positions, Claude returns JSON with translations and optionally corrected reading order

### Requirement: Six translation directions
The system SHALL support translation between any pair of: Japanese (ja), English (en), Traditional Chinese (zh-Hant). This includes all six directed pairs.

#### Scenario: All language pairs available
- **WHEN** user opens the language selection UI
- **THEN** source and target language dropdowns each contain Japanese, English, and Traditional Chinese, and any combination is selectable (except same source and target)

### Requirement: LLM JSON response parsing with retry
The system SHALL parse LLM translation responses as JSON arrays. If parsing fails, the system SHALL retry the request up to 2 times. If all retries fail, the system SHALL fall back to line-by-line text parsing.

#### Scenario: Malformed JSON response
- **WHEN** the LLM returns invalid JSON on first attempt
- **THEN** the system retries, and if the retry returns valid JSON, uses that result

#### Scenario: All retries fail
- **WHEN** the LLM returns invalid JSON on all 3 attempts
- **THEN** the system falls back to splitting the response by newlines and matching to bubbles by position
