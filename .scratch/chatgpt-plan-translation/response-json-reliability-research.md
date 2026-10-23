# ChatGPT Plan Responses JSON reliability

Researched: 2026-10-23
Scope: official OpenAI guidance relevant to intermittent malformed multi-page
translation JSON from the streaming ChatGPT Plan Responses integration. No app
code was changed.

## Finding

The observed `MultiPageParseError.malformedJSON` is not evidence that the SSE
decoder necessarily lost data. It can be a completed response whose free-form
text does not obey the prompt's JSON contract. The current ChatGPT Plan request
relies on that prompt contract because it must stream and cannot send
`max_output_tokens` on this OAuth route.

OpenAI's normal Responses API solution for this class of problem is Structured
Outputs: supply `text.format` with a strict `json_schema`. Unlike JSON mode,
Structured Outputs is intended to make the response adhere to the supplied
schema. It is the best candidate to eliminate free-form JSON drift, **provided
that it is accepted by the selected ChatGPT Plan model and OAuth route**.
[Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)

## Constraints that change the fix

- The ChatGPT Plan preview requires `store: false`, `stream: true`, and complete
  request context in `input`. It explicitly forbids `max_output_tokens` (as
  well as sampling controls). Therefore increasing the output cap is not a
  valid Plan-engine fix, even though it is valid for normal API-key Responses
  requests. [Plan preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- The Plan limitations page does not explicitly list `text.format`/Structured
  Outputs as either supported or unsupported. Treat support as an account/model
  capability to verify with a minimal real request, rather than assuming that
  ordinary Responses API support implies Plan-route support.
- Even Structured Outputs does not make partial or refused responses usable.
  OpenAI documents refusals and incomplete responses (including token-limit
  termination) as cases where a schema-matching payload may not exist.
  [Structured-output edge cases](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)
- Strict schemas need a root object; all object fields must be `required`, and
  objects need `additionalProperties: false`. The existing optional
  `detected_terms` should be represented as a required nullable field or, more
  simply, always as an array (including `[]`).
  [Supported schemas](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)

## Recommended validation spike

1. Send one small ChatGPT Plan request with the existing required streaming
   fields plus a `text.format` `json_schema` mirroring `LLMMultiPageResponse`:
   `pages` array; every page requires `page_id`, `bubbles`, and
   `detected_terms`; every bubble requires `index` and `translation`; all
   objects set `additionalProperties: false`; use `strict: true`.
2. If the API accepts it for an eligible account/model, preserve the existing
   semantic validation of page IDs and bubble indices, but remove reliance on
   prompt-only JSON formatting. Handle an explicit refusal separately.
3. If it is rejected on the Plan route, retain prompt JSON but reduce the
   output surface: translate one page per request (or cap bubbles per request),
   then retry a malformed completed response once using the same small unit.
   This is an application-level reliability fallback, not an API guarantee.

## Streaming completion rule

Accumulate only `response.output_text.delta` events, then parse only after a
terminal `response.completed`. Treat `error`, `response.failed`, and
`response.incomplete` as provider failures, never as JSON to parse. OpenAI
lists these as the important Responses streaming lifecycle signals.
[Streaming Responses](https://developers.openai.com/api/docs/guides/streaming-responses)

The current SSE decoder already rejects `response.incomplete`; retain that
behavior, but expose the terminal reason in a sanitized user-facing error so it
is distinguishable from a malformed *completed* model response.

For API-key Responses (not ChatGPT Plan), `max_output_tokens` includes visible,
reasoning, and other generated tokens. A response ending at that limit has
`status: "incomplete"` and reason `max_output_tokens`; reserve headroom and
check that status before decoding. [Token counting](https://developers.openai.com/api/docs/guides/token-counting)

## Eligibility is not a parser remedy

ChatGPT Plan use is previewed and is limited to eligible users/accounts/models.
A `403 subscription_sharing_user_not_eligible` should be surfaced as an
eligibility problem and should not trigger repeated OAuth attempts. It does not
explain a successfully completed response with malformed JSON, but it matters
when testing the Structured Outputs spike.
[Plan errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery)

## Decision

Do not change the parser to silently repair arbitrary malformed JSON. First run
the schema-support spike. If supported, use strict `text.format` schema output;
if not, shrink/retry request units and improve terminal-error classification.
Both paths keep the parser's current page/bubble correspondence checks, which
prevent a valid-looking response from being applied to the wrong bubble.
