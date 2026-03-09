## 1. Tests

- [x] 1.1 Write test: `userPrompt` uses `bubble.index` not enumeration offset (verify indices [0, 2, 3] are preserved after filtering)
- [x] 1.2 Write test: parser uses dictionary lookup — correct bubble is matched when indices are non-sequential
- [x] 1.3 Write test: parser silently drops items whose index is not in original bubble set
- [x] 1.4 Write test: system prompt does NOT contain "reorder" instruction

## 2. Fix userPrompt

- [x] 2.1 In `LLMPrompt.userPrompt`, change `{"index": \(i), ...}` to `{"index": \(bubble.index), ...}`

## 3. Fix system prompt

- [x] 3.1 In `LLMPrompt.systemPrompt`, remove the "reorder" sentence and the "corrected reading order" instruction
- [x] 3.2 Add instruction: "Echo back the `index` field exactly as given — do not change or reorder indices."

## 4. Fix parser

- [x] 4.1 In `LLMResponseParser.parse`, build a dictionary: `let bubbleByIndex = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.index, $0) })`
- [x] 4.2 Replace `bubbles[item.index]` lookup with `bubbleByIndex[item.index]`
- [x] 4.3 In `TranslatedBubble` initialisation, set `index: originalBubble.index` (not `item.index`)

## 5. Verify

- [x] 5.1 Run all tests and confirm they pass
- [x] 5.2 Manual smoke test: translate a page with punctuation-only bubbles mixed in, verify all translations appear in correct bubbles
