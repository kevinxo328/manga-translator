## Context

The current translation pipeline executes from a `@MainActor` view model into OCR routing and OCR services. In the PaddleOCR path, heavy inference work is synchronous and can run on the UI-critical execution path, causing visible freezes during page translation. The project already has strict OCR routing and error contracts, so the design must improve responsiveness without changing recognition behavior or fallback semantics.

## Goals / Non-Goals

**Goals:**
- Keep SwiftUI responsive while OCR is running in high-accuracy mode.
- Preserve current OCR routing decisions and strict error propagation behavior.
- Preserve baseline high-accuracy OCR text output exactly on the regression dataset.
- Add automated regression coverage for non-blocking behavior and output parity.

**Non-Goals:**
- Changing OCR model weights, prompt strategy, or decode heuristics.
- Reducing batch concurrency as a first-step optimization.
- Introducing new external services or changing user-visible OCR settings.

## Decisions

### 1) Split execution contexts: OCR compute off main actor, UI state on main actor
- **Decision:** Move OCR-heavy compute boundaries (`recognizeAndCluster` pipeline and high-accuracy inference calls) into a dedicated non-main execution context (actor-backed or task-isolated worker), while keeping UI state mutation in `TranslationViewModel` on `MainActor`.
- **Why:** This directly addresses beachball freezes by removing long-running OCR compute from UI-critical execution.
- **Alternative considered:** Keep current `@MainActor` chain and rely on throttling. Rejected because it does not guarantee responsiveness and leaves core blocking behavior unchanged.

### 2) Keep routing and strict-mode failure semantics unchanged
- **Decision:** Do not modify `OCRRouter` selection criteria or strict no-fallback behavior when PaddleOCR fails.
- **Why:** Existing specs and tests depend on this contract; responsiveness work should not change OCR correctness semantics.
- **Alternative considered:** Add fallback when high-accuracy is slow/fails. Rejected because this is behaviorally different and risks output inconsistency.

### 3) Introduce parity gate for recognition output
- **Decision:** Define regression checks that compare optimized high-accuracy OCR text output to the baseline dataset with exact string match.
- **Why:** The user requirement is “no recognition quality drop,” and exact parity provides an objective release gate.
- **Alternative considered:** Metric-based tolerance (CER/WER thresholds). Rejected for this change because it allows drift.

### 4) Apply TDD sequence to concurrency refactor
- **Decision:** Add failing tests first for non-blocking behavior and parity, then refactor execution boundaries, then stabilize race-sensitive paths.
- **Why:** Actor/thread-boundary changes are risky; tests reduce regression risk and protect behavior.
- **Alternative considered:** Refactor first then backfill tests. Rejected due to high chance of latent race or behavior regressions.

## Risks / Trade-offs

- **[Risk]** Actor boundary mistakes can introduce state races or reentrancy bugs.  
  **→ Mitigation:** Keep all view/page state writes on `MainActor`; isolate OCR compute entrypoint behind one async boundary and add concurrency tests.

- **[Risk]** Moving OCR off main actor may expose thread-safety issues in existing recognizer/runtime objects.  
  **→ Mitigation:** Retain existing runtime serialization mechanisms (e.g., lock/actor), and validate with repeated batch/retranslate scenarios.

- **[Risk]** Output parity could accidentally drift during refactor.  
  **→ Mitigation:** Add exact-text parity checks against the baseline set and block completion unless parity passes.

- **[Trade-off]** Additional async hops may add small overhead per request.  
  **→ Mitigation:** Prioritize responsiveness and maintain current batching policy; optimize overhead only if measurements show material impact.

## Migration Plan

1. Add non-blocking and output-parity tests (expected failing baseline where appropriate).
2. Refactor OCR execution boundary to non-main context while keeping UI updates on main actor.
3. Update affected mocks/stubs and router/service tests for new async boundaries.
4. Run OCR routing, high-accuracy OCR, and E2E suites; confirm parity and responsiveness requirements.
5. Ship without user-facing setting changes; rollback path is reverting boundary refactor and keeping existing contracts.

## Open Questions

- Should non-blocking responsiveness be enforced as a hard timing threshold in CI, or as deterministic “main actor remains schedulable” behavioral tests only?
- Do we need a dedicated benchmark fixture set for parity beyond current regression crops before implementation starts?
