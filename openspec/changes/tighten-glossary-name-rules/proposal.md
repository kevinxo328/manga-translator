## Why

Glossary names currently allow ambiguous duplicate labels and silently truncate names longer than 20 Swift `Character` values. This makes glossary pickers harder to trust and can persist names the user did not explicitly choose.

## What Changes

- Reject duplicate glossary names after trimming leading and trailing whitespace/newlines.
- Treat duplicate comparison as exact, case-sensitive comparison of the normalized persisted name.
- Replace silent over-20-character truncation with `GlossaryValidationError.nameTooLong(max: 20)`.
- Keep empty or whitespace-only names rejected with `GlossaryValidationError.emptyName`.
- Surface validation failures consistently in create and rename UI flows without mutating database rows or in-memory selection state.
- **BREAKING**: Callers that relied on automatic truncation of glossary names longer than 20 Swift `Character` values must handle a validation error instead.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `glossary-management`: Tighten glossary name validation for create and rename, including duplicate rejection, explicit length errors, and UI-visible validation behavior.

## Impact

- `GlossaryService` name normalization and validation behavior.
- `GlossaryValidationError` cases and caller error handling.
- Glossary create and rename flows in `TranslationViewModel` and the Settings Glossary tab.
- Unit and UI-adjacent tests for create, rename, duplicate, empty, and length validation.
