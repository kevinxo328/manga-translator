# 01: Add ChatGPT Plan strict structured-output compatibility

**What to build:** A ChatGPT Plan user can translate a multi-page batch with a
strict structured response when the selected model accepts it. If that model
explicitly rejects structured output, the same translation is transparently
retried with the compatible prompt-only response format and that unsupported
capability is remembered for seven days.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The first real batch request for a model without an unexpired negative
  capability result uses strict JSON-schema structured output matching the
  multi-page translation contract.
- [ ] A completed structured response still requires exact requested page and
  bubble correspondence before any translation is applied.
- [ ] A provider rejection specifically caused by unsupported structured output
  retries the same batch using the compatible prompt-only request, without
  changing the user's model or translation engine.
- [ ] The model-keyed unsupported result persists for seven days; expiry permits
  a later structured-output attempt, while temporary provider and stream
  failures do not mark the model unsupported.
- [ ] Stubbed HTTP/SSE tests cover strict request shape, success, rejection and
  compatible retry, cache expiry, incomplete streams, refusals, malformed
  completed output, and sanitized diagnostics without a real account.
