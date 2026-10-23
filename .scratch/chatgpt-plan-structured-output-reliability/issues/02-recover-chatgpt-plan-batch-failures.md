# 02: Recover ChatGPT Plan batch failures page by page

**What to build:** A ChatGPT Plan user whose batch cannot be completed after a
retry receives translations for recoverable pages through page-by-page fallback.
Successful recovery remains silent; a page that cannot be recovered shows a
friendly retryable error rather than an internal parser error.

**Blocked by:** 01: Add ChatGPT Plan strict structured-output compatibility.

**Status:** ready-for-agent

- [ ] A failed ChatGPT Plan batch is retried once before fallback begins, while
  cancellation still immediately preserves pending work.
- [ ] A second failed batch translates its pages individually in page order and
  retains the normal rolling translation context.
- [ ] Successful retry or page-by-page recovery does not show an error message.
- [ ] An unrecoverable page preserves retryable state and reports a clear
  user-facing response failure without exposing Swift error enum details.
- [ ] Existing batch-scheduler tests cover retry, page order, completed-page
  retention, cancellation, and the final friendly failure state without live
  network access.
