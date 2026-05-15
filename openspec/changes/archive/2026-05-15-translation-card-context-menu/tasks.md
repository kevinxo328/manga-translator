## 1. Clipboard Abstraction

- [x] 1.1 Define `ClipboardWriting` protocol with `write(_ string: String) -> Bool`
- [x] 1.2 Implement `NSPasteboardClipboard` (production): `clearContents()` then `setString(_:forType: .string)`, return Bool result
- [x] 1.3 Implement `FakeClipboard` (test double): captures `lastWritten: String?`, configurable `shouldSucceed: Bool`

## 2. Tests (write first, watch fail)

- [x] 2.1 Write test: "Copy Translation" calls `write(bubble.translatedText)` on injected clipboard
- [x] 2.2 Write test: "Copy Original Text" calls `write(bubble.bubble.text)` with full untruncated string
- [x] 2.3 Write test: "Copy Both" calls `write("Original: …\nTranslation: …")` with correct format
- [x] 2.4 Write test: clipboard write returning `false` does not crash
- [x] 2.5 Write test: empty `translatedText` writes empty string without error

## 3. Implementation

- [x] 3.1 Add `ClipboardWriting` parameter to `TranslationCard` (default: `NSPasteboardClipboard()`)
- [x] 3.2 Add `.contextMenu` modifier to `TranslationCard.body` with three `Button` actions
- [x] 3.3 Implement "Copy Translation" action using injected clipboard
- [x] 3.4 Implement "Copy Original Text" action using injected clipboard
- [x] 3.5 Implement "Copy Both" action with `"Original: \(bubble.bubble.text)\nTranslation: \(bubble.translatedText)"` format

## 4. Verification

- [x] 4.1 Run unit tests — all pass, no global pasteboard touched
- [x] 4.2 Manual smoke test: right-click card → "Copy Translation" → paste, confirm full translation text
- [x] 4.3 Manual smoke test: right-click card → "Copy Original Text" → paste, confirm full OCR text (not truncated)
- [x] 4.4 Manual smoke test: right-click card → "Copy Both" → paste, confirm `Original: …\nTranslation: …` format
