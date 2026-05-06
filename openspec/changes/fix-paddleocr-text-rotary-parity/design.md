## Context

The current Swift PaddleOCR runtime diverges from the verified reference path in `scripts/convert_model/verify.py`. Investigation narrowed the main failure mode to the text-side runtime: image preprocessing, projected image features, and merged embeddings are already close enough to the reference path, but the Swift text model produces first-step `EOS` and newline outputs on crops where the reference path emits real text.

The strongest confirmed mismatch is inside the Swift PaddleOCR text-model rotary path. In the current Swift package, `ERNIEAttention` applies `MLXFast.RoPE(...)` directly. Investigation shows q/k tensors are still close before rotary application, but diverge sharply immediately after rotary application, and the divergence then compounds through attention, hidden states, and final logits.

This change touches multiple layers of the OCR stack:
- Swift package text-model runtime
- app-side PaddleOCR integration
- benchmark and crop-level regression validation
- temporary investigation hooks that should not remain as production code

## Goals / Non-Goals

**Goals:**
- Restore text-side rotary parity between the Swift PaddleOCR runtime and the verified reference implementation.
- Eliminate the confirmed empty-output and newline-only first-step failures on known benchmark crops.
- Add regression coverage that checks crop-level runtime parity and protects the known benchmark-empty cases.
- Clean up investigation-only debug/export hooks after the fix is validated.

**Non-Goals:**
- This change does not try to solve every remaining OCR quality delta in one pass.
- This change does not retune detector crop expansion, interpolation, or text post-processing beyond what is required to keep regression tests accurate.
- This change does not redesign the benchmark architecture or replace the current PaddleOCR integration strategy.

## Decisions

### Replace `MLXFast.RoPE(...)` with a PaddleOCR-compatible text rotary implementation

The Swift text runtime should not keep using `MLXFast.RoPE(...)` directly for PaddleOCR-VL text attention. Investigation confirmed that q/k tensors stay close before rotary and diverge immediately after rotary, which makes this the first confirmed primary runtime fault rather than a downstream symptom.

Chosen approach:
- implement a custom Swift rotary helper for the PaddleOCR text model
- compute rotary cos/sin values with the same parameterization used by the verified reference path
- apply rotary to q/k explicitly inside `ERNIEAttention`
- keep the implementation structure close to the reference path so parity checks remain straightforward

Alternatives considered:
- Keep `MLXFast.RoPE(...)` and tune other parts of the runtime.
  - Rejected because the investigation already proved the first major divergence starts at rotary application.
- Patch around the issue with stop-token or decoder heuristics.
  - Rejected because that would only mask downstream failures and would not restore first-step parity.

### Fix the root cause before secondary OCR quality factors

There are other confirmed contributing factors, including `min_pixels`, decoder guards, and post-processing cleanup. They should not be mixed into the primary text-runtime fix until the rotary change is validated in isolation.

Chosen approach:
- first land the text-side rotary fix
- validate known empty cases and first-step token behavior
- then apply smaller quality fixes in a controlled follow-up sequence if needed

Alternatives considered:
- Bundle all known OCR quality fixes into one large patch.
  - Rejected because it would make it difficult to attribute outcome changes and would weaken regression confidence.

### Add permanent regression coverage at crop level

The existing benchmark is useful for end-to-end validation, but it is not sufficient on its own to catch text-runtime parity regressions. This change should leave behind targeted regression tests that operate on known problematic crops.

Chosen approach:
- add crop-level regression checks for the known benchmark-empty cases
- validate that first-step outputs are no longer `EOS` or newline on those cases
- keep a narrow parity-oriented test surface that is stable enough for long-term maintenance

Alternatives considered:
- Rely only on `OCRBenchmarkTests/testFullBenchmark`.
  - Rejected because it mixes multiple factors and does not isolate runtime parity failures well enough.

### Remove or isolate investigation-only debug hooks after validation

The current investigation introduced extra export and trace hooks to inspect tensors, logits, and layer states. Those were necessary to isolate the root cause, but they should not remain as permanent production-path surface area.

Chosen approach:
- keep debug hooks only long enough to validate the rotary fix
- then delete them or restrict them to test-only / debug-only scope
- preserve only the regression tests and the investigation note as durable artifacts

Alternatives considered:
- Keep all debug export APIs indefinitely.
  - Rejected because they expand production runtime surface area without user value.

## Risks / Trade-offs

- [Risk] The Swift package may contain more than one text-side numeric mismatch. → Mitigation: validate the rotary fix against the known empty cases first and retain crop-level parity tests before removing debug instrumentation.
- [Risk] Fixing rotary may improve empty outputs but still leave smaller recognition deltas. → Mitigation: keep secondary contributing factors out of the first fix, then evaluate remaining issues separately with the same benchmark set.
- [Risk] The implementation may temporarily require patching code inside the checked-out Swift package dependency. → Mitigation: keep the change localized, document it in the change artifacts, and minimize nonessential edits around the dependency.
- [Risk] Removing debug hooks too early could make regression diagnosis expensive. → Mitigation: only remove them after the known empty cases and benchmark regressions are green.
