## MODIFIED Requirements

### Requirement: Support DeepL translation backend
The system SHALL support DeepL API as a translation backend. DeepL SHALL translate each bubble independently via the DeepL REST API. DeepL language-code mapping SHALL support every language in the target language list.

#### Scenario: DeepL translates Japanese to Traditional Chinese
- **WHEN** user selects DeepL engine and translates a page from Japanese to Traditional Chinese
- **THEN** each bubble is sent to DeepL API and the translated text is returned

#### Scenario: DeepL maps expanded target languages
- **WHEN** user selects any supported target language
- **THEN** DeepL requests SHALL use the provider language code for that target language

### Requirement: Support Google Translate backend
The system SHALL support Google Cloud Translation API as a translation backend. Google language-code mapping SHALL support every language in the target language list.

#### Scenario: Google translates English to Japanese
- **WHEN** user selects Google engine and translates a page from English to Japanese
- **THEN** each bubble is sent to Google Cloud Translation API and the translated text is returned

#### Scenario: Google maps expanded target languages
- **WHEN** user selects any supported target language
- **THEN** Google Translate requests SHALL use the provider language code for that target language

### Requirement: Supported translation languages
The system SHALL support English and Japanese as source languages. The system SHALL support English, French, German, Indonesian, Japanese, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, Traditional Chinese, and Vietnamese as target languages. Source and target language lists SHALL be sorted A-Z by English display name. Any valid combination SHALL be selectable, including same-language pairs; same-language execution behavior is owned by the pipeline skip optimization capability.

#### Scenario: All language pairs available
- **WHEN** user opens the language selection UI
- **THEN** the source language dropdown contains English and Japanese in that order
- **AND** the target language dropdown contains English, French, German, Indonesian, Japanese, Korean, Portuguese (Brazil), Simplified Chinese, Spanish, Traditional Chinese, and Vietnamese in that order
