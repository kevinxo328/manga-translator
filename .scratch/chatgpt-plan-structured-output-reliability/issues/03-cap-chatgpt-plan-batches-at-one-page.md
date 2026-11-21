# 03: Cap ChatGPT Plan batches at one page

**What to build:** Keep ChatGPT Plan translation requests to one page per
request because larger streamed responses can stall before `response.completed`.
Other translation engines retain their existing batch limits and ramp-up rules.

**Status:** ready-for-human

- [x] ChatGPT Plan sends at most one page per request.
- [x] Other engines keep their existing batch behavior.
- [x] Regression tests cover the single-page ChatGPT Plan scheduler behavior.
- [x] Existing retry and per-page recovery tests remain passing.

## Rationale

Session `E4DC70B5-1AAB-4298-9E31-5838ACEE071D` showed that one-page requests
completed, while repeated three-page ChatGPT Plan requests timed out before the
terminal response event.
