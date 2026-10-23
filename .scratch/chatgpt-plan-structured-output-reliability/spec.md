# ChatGPT Plan structured-output reliability

**Status:** ready-for-agent

## Problem Statement

When ChatGPT Plan translates several manga pages in one request, the model
occasionally returns free-form text that is not valid JSON for the required
multi-page response. The app exposes an internal
`MultiPageParseError.malformedJSON` error and leaves the batch pending, even
though the same pages could often be translated by a compatible request format
or by smaller requests.

## Solution

For ChatGPT Plan batch translation only, request strict JSON-schema structured
output on the first real translation for a selected model. If the Plan route
explicitly rejects structured output, remember that model capability for seven
days and transparently use the existing prompt-only JSON request format. For
recoverable translation failures, retry the batch once and then translate the
pages individually. Successful recovery is silent; only unrecoverable failure
is shown as a friendly retryable message.

## User Stories

1. As a ChatGPT Plan user, I want multi-page translation responses to match the
   app's required page and bubble structure, so that valid translations are not
   lost to free-form JSON formatting mistakes.
2. As a user, I want the app to use strict structured output when my selected
   model supports it, so that my translation succeeds reliably without extra
   setup.
3. As a user, I want the first actual translation to establish compatibility,
   so that selecting a model does not spend plan usage on a separate probe.
4. As a user whose selected model does not support strict structured output on
   the ChatGPT Plan route, I want translation to continue automatically using
   the compatible request format, so that I can retain my model choice.
5. As a user, I want the app to remember an unsupported capability temporarily,
   so that repeated app launches do not repeatedly send a known-invalid request.
6. As a user, I want capability information retried after seven days, so that a
   later provider-side capability change can take effect without manual action.
7. As a user, I want a transient batch failure retried once, so that brief
   provider and transport failures do not interrupt my work.
8. As a user, I want a repeatedly failing batch retried page by page, so that a
   difficult page does not prevent other pages from being translated.
9. As a user, I want successful fallback to remain unobtrusive, so that normal
   work is not interrupted by provider implementation details.
10. As a user, I want an unrecoverable translation error to explain that the
    response was incomplete or unusable and can be retried, so that I am not
    shown an internal Swift error code.
11. As a privacy-conscious user, I want diagnostics to retain only sanitized
    failure classification and metadata, so that manga text and OAuth tokens do
    not enter logs.
12. As a user, I want ChatGPT Plan's normal batch size and cross-page context
    retained when requests succeed, so that reliability improvements do not
    reduce translation quality or throughput.

## Implementation Decisions

- The scope is limited to ChatGPT Plan batch translation. API-key OpenAI,
  GitHub Copilot, DeepL, and Google behavior remains unchanged.
- The initial request for a model with no unexpired negative capability record
  uses Responses structured output with a strict JSON schema matching the
  existing multi-page response contract.
- The schema has a root object; every object disallows additional properties;
  every declared field is required. Detected terms are always represented by an
  array, including an empty array, rather than an omitted field.
- Existing semantic checks remain authoritative: every requested page identifier
  and bubble index must appear exactly once. Structured output guarantees shape,
  not correspondence to the input batch.
- A request rejection that specifically identifies unsupported structured-output
  capability records a seven-day, model-keyed negative capability result and
  immediately resends the same translation through prompt-only JSON.
- Transport errors, provider refusals, unavailable-plan errors, incomplete
  streams, and parse failures do not establish an unsupported capability. They
  follow normal recovery instead.
- A completed batch that fails is retried once. If it still fails, its pages are
  translated one by one in page order, preserving the normal rolling-context
  behavior. Cancellation still stops work immediately.
- An individual page that cannot be recovered stays retryable and receives a
  friendly user-facing error. Provider API failures that must remain explicit
  continue to do so; no other translation engine is selected automatically.
- Successful structured-output fallback and per-page recovery do not display a
  notification. Sanitized diagnostic events distinguish unsupported capability,
  incomplete stream, malformed completed output, retry, and final failure.
- The existing batch limits remain unchanged: up to five pages and 45 bubbles,
  with the existing single-page oversize behavior.

## Testing Decisions

- Tests assert user-observable request, recovery, and page-state behavior, not
  SwiftUI implementation details or a real provider account.
- At the ChatGPT Plan translation-service seam, stubbed HTTP/SSE tests verify
  the strict-schema request format, successful decoding, a structured-output
  rejection followed by prompt-only retry, the seven-day capability expiry, and
  classification of incomplete, refusal, and malformed completed responses.
- At the existing batch-scheduler view-model seam, tests verify one batch retry,
  page-order individual fallback, retained completed pages, cancellation, and
  the friendly final failure state for ChatGPT Plan.
- Existing parser tests remain the contract for strict page and bubble
  correspondence validation. Tests must prove that neither access tokens nor
  response text are logged.

## Out of Scope

- Changing normal batch size, adding input-token sizing, or splitting a single
  page into smaller translation requests.
- A separate network request made solely to probe model support.
- Modifying the selected model, switching translation engines, or bypassing
  ChatGPT Plan availability and eligibility failures.
- Adding Structured Outputs to other translation engines.
- Repairing arbitrary invalid JSON instead of using a schema or controlled
  recovery.

## Further Notes

The capability result is a compatibility cache, not an account credential and
not proof of model availability. OpenAI's public Structured Outputs guidance
supports strict JSON schema for compatible modern models; the ChatGPT Plan
preview contract must still be treated as runtime-authoritative. Research is
recorded in the adjacent response-JSON reliability note.
