## MODIFIED Requirements

### Requirement: Use fixed log levels and categories
The system SHALL classify debug events using exactly the V1 log levels `debug`, `info`, `warning`, `error`, and `fault`. The system SHALL classify event category using the V1 category dictionary.

#### Scenario: Filterable level value
- **WHEN** an event is persisted
- **THEN** its level SHALL be one of `debug`, `info`, `warning`, `error`, or `fault`

#### Scenario: Filterable category value
- **WHEN** an event is persisted
- **THEN** its category SHALL be one of `app.lifecycle`, `settings`, `file.input`, `ocr.router`, `ocr.manga`, `ocr.paddle`, `translation.openai`, `translation.google`, `translation.deepl`, `translation.copilot`, `cache`, `model.download`, `keychain`, `export`, `debug.log`, or `pipeline`
