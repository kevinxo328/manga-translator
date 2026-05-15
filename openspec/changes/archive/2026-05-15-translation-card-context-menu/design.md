## Context

The translation sidebar renders a list of `TranslationCard` views. Each card shows `bubble.translatedText` (full) and `bubble.bubble.text` (truncated to 2 lines by `lineLimit`). There is currently no clipboard shortcut beyond SwiftUI's built-in `.textSelection(.enabled)` on individual text fields.

## Goals / Non-Goals

**Goals:**
- Add right-click context menu to every `TranslationCard` with three clipboard actions
- Copy operations always use the complete strings, never the visually truncated versions
- Clipboard writes are safe: stale content is never silently left on the pasteboard

**Non-Goals:**
- Keyboard shortcuts for copy (out of scope)
- Editing translation content from the sidebar
- Batch copy across multiple cards

## Decisions

### Use `.contextMenu` on `TranslationCard`

SwiftUI's `.contextMenu { }` modifier on macOS triggers on right-click/Control-click and renders native `NSMenu`. Applied directly to `TranslationCard`'s body so the card is self-contained.

Alternatives considered:
- Apply on the `Button` wrapper in `TranslationSidebar` — same visual result but leaks menu logic into the parent; less cohesive.
- Custom `NSMenu` via `NSViewRepresentable` — unnecessary complexity for three simple actions.

### Injectable clipboard abstraction (`ClipboardWriting` protocol)

Copy actions are not implemented against `NSPasteboard.general` directly. Instead, a `ClipboardWriting` protocol is defined:

```swift
protocol ClipboardWriting {
    @discardableResult
    func write(_ string: String) -> Bool
}
```

`NSPasteboardClipboard` (production) implements it by calling `clearContents()` then `setString(_:forType:)` on `NSPasteboard.general` and returning the Boolean result. Tests inject a `FakeClipboard` that captures the last written string and exposes a `lastWritten` property.

This makes all three copy actions fully unit-testable without touching global state and without a UI-test harness.

**Why not test `NSPasteboard.general` directly?**  
Global pasteboard state is shared across all concurrently running tests and between test runs and the developer's actual clipboard. Using a named pasteboard or a fake avoids both flakiness and UX disruption.

### Clipboard write must call `clearContents()` first

`NSPasteboard.general.setString(_:forType:)` returns `false` if the pasteboard is locked or has an incompatible owner. Calling `clearContents()` first resets ownership, making the write reliable. The `write(_:)` implementation SHALL:

1. Call `clearContents()`
2. Call `setString(_:forType: .string)`
3. Return the Boolean result

### "Copy Both" format

```
Original: <bubble.bubble.text>
Translation: <bubble.translatedText>
```

Two labelled lines separated by a newline — readable when pasted into any plain-text context.

### Context menu activation vs. highlight toggle

`.contextMenu` on macOS consumes the right-click before it can propagate a highlight toggle. This is acceptable — left-click still toggles highlight as before. This trade-off is intentional and does not need mitigation.

### Test strategy

| Concern | Approach |
|---------|----------|
| Copy action logic (all 3 actions) | Unit tests with `FakeClipboard` — fast, isolated, no global state |
| Context menu item presence (right-click UI) | Manual smoke test — no ViewInspector harness available in this repo |
| Clipboard write failure path | Unit test: `FakeClipboard` configured to return `false`; verify no crash |

## Risks / Trade-offs

- Right-click context menu presence cannot be covered by automated tests given the current test infrastructure. A documented manual smoke test is the accepted mitigation.
- `clearContents()` is a global side effect even with the abstraction — production usage still clears the real pasteboard. This is expected AppKit behaviour.

## Open Questions

(none)
