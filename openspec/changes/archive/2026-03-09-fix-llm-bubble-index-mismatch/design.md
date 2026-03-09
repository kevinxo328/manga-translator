## Context

LLM translation sends bubbles with sequential indices (0, 1, 2...) and a system prompt that instructs the LLM to "reorder" bubbles if the reading order seems wrong. The parser then uses the returned `index` as a direct array lookup (`bubbles[item.index]`). When LLM changes the index order (as instructed), translations end up in the wrong bubbles.

Additionally, `userPrompt` uses the enumeration offset `i` rather than `bubble.index`, so after punctuation-only filtering the indices sent to LLM may not match the original `BubbleCluster.index` values.

## Goals / Non-Goals

**Goals:**
- Ensure LLM always echoes back indices unchanged so parser can safely look up the correct bubble
- Use `bubble.index` (true reading-order index) in user prompt instead of enumeration offset
- Replace array-index lookup with dictionary lookup to prevent out-of-bounds and mismatches

**Non-Goals:**
- Changing reading-order sorting logic (handled by `ReadingOrderSorter`)
- Adding smart reordering based on LLM judgment (future work if needed)
- Changing UI, data models, or cache format

## Decisions

### Remove "reorder" instruction from system prompt
The current prompt says "if reading order seems incorrect, reorder them" — this is the direct cause of the bug. LLM-driven reordering requires a different contract (e.g., returning original index + display order as separate fields). Since reading order is already handled by `ReadingOrderSorter` before translation, we remove the instruction entirely.

**Alternative considered**: Keep reorder instruction, add separate `original_index` field. Rejected — more complex prompt engineering, more surface area for LLM to get wrong.

### Use `bubble.index` in userPrompt instead of enumeration `i`
`toTranslate` is a filtered subset; its enumeration offset `i` diverges from the original `bubble.index`. Using `bubble.index` makes the contract consistent: what LLM receives equals what parser expects.

### Dictionary lookup in parser
Replace `bubbles[item.index]` with a dictionary keyed by `bubble.index`. This is safe even if LLM skips an index or returns an out-of-range value — the `compactMap` guard handles missing keys gracefully.

## Risks / Trade-offs

- [LLM may still attempt reordering despite updated prompt] → The dictionary lookup now makes it safe: if LLM returns an index it wasn't given, that item is simply dropped via `compactMap`
- [Removing reorder instruction loses LLM's ability to correct bad OCR order] → Reading order is already handled by ReadingOrderSorter; LLM reordering was a workaround, not the intended design
