# Spec: Translation Card Context Menu

## Purpose

Provide quick clipboard copy actions on each translation card in the sidebar, allowing users to copy translated text, original OCR text, or both with a single right-click.

## Requirements

### Requirement: Context menu on translation card
Each `TranslationCard` in the translation sidebar SHALL present a right-click context menu with three copy actions: Copy Translation, Copy Original Text, and Copy Both.

#### Scenario: Right-click shows menu
- **WHEN** the user right-clicks (or Control-clicks) a translation card
- **THEN** a context menu appears with three items: "Copy Translation", "Copy Original Text", "Copy Both"

### Requirement: Copy Translation
Selecting "Copy Translation" SHALL write the card's full translated text to the clipboard via the injected `ClipboardWriting` implementation.

#### Scenario: Copy translation to clipboard
- **WHEN** the user selects "Copy Translation" from the context menu
- **THEN** `bubble.translatedText` is written to the clipboard

#### Scenario: Copy translation with empty text
- **WHEN** the user selects "Copy Translation" and `bubble.translatedText` is an empty string
- **THEN** an empty string is written to the clipboard without error

### Requirement: Copy Original Text
Selecting "Copy Original Text" SHALL write the card's full OCR-recognized text to the clipboard, without any `lineLimit` truncation.

#### Scenario: Copy full original text
- **WHEN** the user selects "Copy Original Text" from the context menu
- **THEN** the complete `bubble.bubble.text` string (not truncated) is written to the clipboard

### Requirement: Copy Both
Selecting "Copy Both" SHALL write a formatted string containing both original and translated text to the clipboard.

#### Scenario: Copy both fields
- **WHEN** the user selects "Copy Both" from the context menu
- **THEN** a string of the form `"Original: <text>\nTranslation: <text>"` is written to the clipboard

### Requirement: Clipboard write safety
The system SHALL clear the pasteboard before writing, using a `ClipboardWriting` abstraction that calls `clearContents()` prior to `setString(_:forType:)`.

#### Scenario: Clipboard cleared before write
- **WHEN** any copy action is triggered
- **THEN** the clipboard is cleared before the new content is written, preventing stale data from persisting if the write fails

#### Scenario: Clipboard write failure does not crash
- **WHEN** the clipboard write returns `false` (e.g., pasteboard locked)
- **THEN** the app does not crash and no stale data is presented as success
