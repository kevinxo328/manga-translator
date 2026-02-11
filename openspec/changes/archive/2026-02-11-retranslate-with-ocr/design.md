## Context

The current re-translate feature (`retranslateFromOCR()`) extracts OCR bubbles from existing translation results and re-runs only the translation step. This means if the original OCR was incorrect (e.g., misread characters, missed bubbles, wrong clustering), re-translate cannot fix it. The only workaround is to clear the entire cache and re-process all pages.

The `translatePage(at:)` method already implements the full OCR → translate → cache pipeline, but it checks cache first and returns early on cache hits. Re-translate needs to run this same pipeline while bypassing the cache lookup.

## Goals / Non-Goals

**Goals:**
- Re-translate performs full OCR + translate pipeline, producing fresh results
- Results are written back to cache, replacing existing entries
- Minimal code changes — reuse existing `translatePage` logic where possible

**Non-Goals:**
- Adding a separate "re-OCR only" button (out of scope)
- Changing the cache key structure or schema
- Modifying the OCR pipeline itself

## Decisions

### Decision 1: Reuse `translatePage` with a `bypassCache` flag

Rather than duplicating the OCR → translate → cache store logic, add a `bypassCache: Bool = false` parameter to `translatePage(at:)`. When `true`, skip the cache lookup step but still store results to cache after completion.

**Rationale**: This avoids code duplication and ensures re-translate always follows the same path as initial translation. The only difference is skipping the cache lookup at the start.

**Alternative considered**: Creating a separate `retranslateWithOCR()` method that calls OCR and translate independently. Rejected because it would duplicate the pipeline logic and diverge over time.

### Decision 2: Remove `retranslateFromOCR()`

The existing `retranslateFromOCR()` method is replaced entirely. There's no use case for re-translating without re-running OCR — if the user wants fresh results, they should get fresh OCR too.

**Rationale**: Simplifies the API surface. One re-translate action that does the complete job.

### Decision 3: Keep `retranslateCurrentPage()` as the public entry point

`retranslateCurrentPage()` already exists and is called from the UI. Update it to call `translatePage(at: currentPageIndex, bypassCache: true)`.

**Rationale**: Minimal UI changes — the button action stays the same, only the underlying behavior changes.

## Risks / Trade-offs

- **[Slower re-translate]** → Re-translate now includes OCR processing, which is slower than translate-only. This is acceptable because correctness matters more than speed, and users explicitly chose to re-translate.
- **[Breaking change for users who relied on OCR reuse]** → Users who changed translation engine and wanted to keep existing OCR results will now get fresh OCR too. This is the desired behavior per the proposal.
