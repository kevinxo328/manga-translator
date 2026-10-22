# 03: Translate with ChatGPT Plan streaming responses

**What to build:** A user who selected ChatGPT Plan and an available model can
translate manga through the direct Responses API, receiving the same translated
bubble behavior and translation context as the existing LLM engine.

**Blocked by:** 01: Authorize and disconnect a ChatGPT Plan account; 02: Select an account-available ChatGPT Plan model.

**Status:** ready-for-agent

- [ ] The engine sends the selected model, current bubbles, glossary, and recent
  page context through the supported streaming Responses request contract and
  converts a completed stream into translated bubbles.
- [ ] A response is accepted only after a successful terminal event; malformed,
  interrupted, authorization, usage, and unavailable-model outcomes propagate
  as ordinary provider errors.
- [ ] Translation batches stop on those errors, preserve untranslated work, and
  never automatically fall back to a different translation engine.
- [ ] Tests cover request shape, SSE accumulation and terminal states, context
  parity, error propagation, and batch behavior through existing service and
  view-model seams.
