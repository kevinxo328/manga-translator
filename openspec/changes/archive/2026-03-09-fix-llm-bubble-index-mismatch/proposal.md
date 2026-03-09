## Why

When LLM translation services process speech bubbles, translations occasionally appear in the wrong bubbles. The system prompt instructs LLM to "reorder" bubbles if reading order seems incorrect, but the parser uses the returned index as an array lookup — causing mismatches when LLM changes the index order.

## What Changes

- Remove "reorder" instruction from LLM system prompt; replace with explicit "echo back index unchanged"
- Fix `LLMPrompt.userPrompt` to use `bubble.index` instead of enumeration offset `i`
- Replace array-index lookup in `LLMResponseParser.parse` with dictionary-based lookup keyed by `bubble.index`

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `translation-service`: LLM index contract changes — indices must be echoed back unchanged; parser uses dictionary lookup instead of array indexing

## Impact

- `MangaTranslator/Services/LLMPrompt.swift` — system prompt and user prompt generation
- No API changes, no UI changes, no data model changes
