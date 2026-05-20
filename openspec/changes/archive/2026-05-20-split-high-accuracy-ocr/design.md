## Context

`high-accuracy-ocr/spec.md` currently contains 10 requirements and 61 scenarios covering several independent ownership areas:

- device capability and local model lifecycle
- model download, verification, deletion, launch verification, and state convergence
- PaddleOCR-VL recognizer runtime behavior
- strict-mode error codes and localization policy
- reproducible model conversion and parity tooling
- page-boundary MLX GPU cache cleanup

This change is a spec-structure refactor. It must preserve the existing behavior contract while making ownership explicit enough for future changes to modify one area without rereading the whole high-accuracy OCR surface.

## Goals / Non-Goals

**Goals:**

- Move every current `high-accuracy-ocr` requirement to a single owner capability.
- Preserve all current scenario semantics, including the deterministic state-machine table and stable PaddleOCR error-code strings.
- Keep `high-accuracy-ocr` as an umbrella capability that describes the end-to-end feature and delegates detailed requirements to the owner capabilities.
- Produce specs that future phases can reference when removing duplicate `paddleocr.enabled` rules from `ocr-routing`, `settings-management`, and `manga-ocr`.
- Record the test ownership map so missing coverage can be handled as explicit tasks instead of hidden assumptions.

**Non-Goals:**

- No production code behavior changes.
- No public API, cache key, model path, model format, runtime algorithm, or translation pipeline changes.
- No rework of `ocr-routing`, `settings-management`, or `manga-ocr` duplicate `paddleocr.enabled` text in this phase; that belongs to Phase 2 after `local-model-lifecycle` exists.
- No UI test expansion for re-translate, batch progress, image viewer hover, keyboard navigation, or translation-engine selection.

## Decisions

### Keep `high-accuracy-ocr` as a thin umbrella

`high-accuracy-ocr` remains as the feature-level entry point because archived changes and adjacent specs already refer to it as the user-facing high-accuracy OCR capability. The detailed behavioral requirements move to narrower owner specs.

Alternative considered: delete `high-accuracy-ocr` entirely. That would remove duplication, but it would make existing references harder to follow and force readers to know all four new capability names before understanding the feature.

### Make `local-model-lifecycle` the owner of capability gating and state convergence

The lifecycle spec owns device capability, download, extraction safety, atomic install, checksum verification, launch verification, delete behavior, and the `ModelDownloadState` + `paddleocr.enabled` state machine. It also owns invalid enabled-state correction.

This choice makes Phase 2 straightforward: `ocr-routing`, `settings-management`, and `manga-ocr` can reference one lifecycle contract instead of restating the same rule in several forms.

### Make `paddleocr-recognizer` the owner of runtime behavior

The recognizer spec owns inference, lazy load, reload/unload, memory pressure, crop boundaries, all-white/all-black behavior, large images, strict-mode recognizer failure behavior, UI-critical execution constraints, decode loop termination, baseline regression preservation, and MLX GPU cache cleanup after PaddleOCR page attempts.

This groups behavior by the runtime component that must satisfy it. Page-boundary MLX GPU cache cleanup stays here because it is specific to PaddleOCR page processing and must preserve recognizer/model reuse semantics.

### Make `paddleocr-error-contract` the owner of stable error codes

The error-contract spec owns the six stable PaddleOCR error codes:

- `paddleocr.download_failed`
- `paddleocr.verify_failed`
- `paddleocr.model_unavailable`
- `paddleocr.inference_failed`
- `paddleocr.storage_unavailable`
- `paddleocr.operation_cancelled`

It also owns the rule that codes are contract keys and must not be used directly as localization keys. This separates telemetry/UI stability from lifecycle and runtime mechanics.

### Make `model-conversion-tooling` the owner of scripts and parity workflow

The tooling spec owns `scripts/convert_model/`, `uv` environment setup, HuggingFace cache location, teardown behavior, quantization sweeps, `verify.py`, detector-derived crops, explicit crop manifests, and crop-level parity gates.

This keeps developer tooling out of runtime specs while preserving the contract that app-aligned crop verification is the primary parity workflow.

### Preserve scenario text before editing wording

The specs phase SHALL first copy requirements and scenarios into their target owner specs with minimal wording changes. Any cleanup SHALL happen only after confirming the scenario count and required constants are preserved.

## Requirement Ownership Map

| Current `high-accuracy-ocr` requirement | Target capability |
| --- | --- |
| Detect device capability for high-accuracy OCR | `local-model-lifecycle` |
| Download high-accuracy OCR model on demand | `local-model-lifecycle` |
| Verify model integrity on app launch | `local-model-lifecycle` |
| Delete high-accuracy OCR model | `local-model-lifecycle` |
| Run high-accuracy OCR inference on Apple Silicon | `paddleocr-recognizer` |
| Stable decode termination for high-accuracy OCR | `paddleocr-recognizer` |
| High-accuracy OCR error contract | `paddleocr-error-contract` |
| Deterministic high-accuracy state machine | `local-model-lifecycle` |
| Reproducible model conversion script | `model-conversion-tooling` |
| Clear MLX GPU buffer cache after PaddleOCR page processing | `paddleocr-recognizer` |

## Scenario Count Check

The current source spec has 61 scenarios. The expected owner-spec distribution is:

| Target capability | Scenario count |
| --- | ---: |
| `local-model-lifecycle` | 27 |
| `paddleocr-recognizer` | 20 |
| `paddleocr-error-contract` | 6 |
| `model-conversion-tooling` | 8 |

The four owner specs total exactly 61 scenarios. The umbrella `high-accuracy-ocr` delta adds delegation scenarios for reader navigation only; those delegation scenarios do not replace or duplicate behavior ownership.

The specs phase MUST avoid semantic duplication: each original behavior scenario SHALL appear in exactly one owner spec. Cross-cutting relationships, such as lifecycle failures that emit stable error codes, SHALL be expressed by referencing the owner capability instead of duplicating the same scenario text.

## Test Ownership Map

| Target capability | Existing test anchors |
| --- | --- |
| `local-model-lifecycle` | `DeviceCapabilityServiceTests`, `ModelDownloadServiceTests`, `PaddleOCRSettingsCapabilityTests`, `PaddleOCRSettingsEnableGatingTests`, `PaddleOCRSettingsEnableRejectionTests`, `PaddleOCRSettingsPreferencePersistenceTests`, `PaddleOCRSettingsDeleteConfirmationTests` |
| `paddleocr-recognizer` | `PaddleOCRVLRecognizerTests`, `DefaultPaddleOCREngineTests`, `MultimodalPositionIdsTests`, `OCRRouterTests.testMainActorResponsivenessDuringOCR`, `OCRRouterTests.testPaddleOCRSuccessPathInvokesCacheCleanupOnce`, `OCRRouterTests.testPaddleOCRFailurePathInvokesCacheCleanupOnce`, `OCRRouterTests.testMangaOCRPathDoesNotInvokeCacheCleanup` |
| `paddleocr-error-contract` | `OCRRouterTests` stable error-code tests and localization-code separation tests |
| `model-conversion-tooling` | `PaddleOCRProductionParityDiagnosticTests`, `PaddleOCRVerificationTests`, conversion-script verification commands under `scripts/convert_model/` |
| `high-accuracy-ocr` umbrella | No direct behavior tests required; it delegates to owner capabilities |

Missing test coverage discovered during task planning SHALL be limited to these four owner areas. Translation UI, image viewer interaction, batch progress display, keyboard navigation, and OpenAI/Copilot request happy paths are intentionally out of scope for this change.

## Migration Plan

1. Create delta specs for the four new capabilities using the ownership map above.
2. Modify `high-accuracy-ocr` to remove detailed duplicated ownership and retain an umbrella feature description that points to the four owner capabilities.
3. Preserve the deterministic state-machine table exactly under `local-model-lifecycle`.
4. Preserve the six stable error-code strings exactly under `paddleocr-error-contract`.
5. Run `openspec validate split-high-accuracy-ocr --strict`.
6. Compare scenario names from the original `high-accuracy-ocr/spec.md` with the new delta specs before archive.
7. Update `PLAN.md` Phase 1 only after specs and tasks validate.

Rollback is straightforward because this phase changes only OpenSpec artifacts: discard the `split-high-accuracy-ocr` change or avoid archiving it.

## Risks / Trade-offs

- Scenario loss during migration -> Mitigate with a scenario-name diff before archive.
- Over-duplicating cross-cutting failures between lifecycle, recognizer, and error contract -> Mitigate by assigning one owner and using references in non-owner specs.
- Future readers missing the umbrella entry point -> Mitigate by keeping `high-accuracy-ocr` as the thin feature-level index.
- Phase 2 depending on an unstable lifecycle owner -> Mitigate by completing `local-model-lifecycle` and validating it before editing `ocr-routing`, `settings-management`, or `manga-ocr`.

## Open Questions

None. Phase 1 will keep `high-accuracy-ocr` as an umbrella spec and split detailed requirements into the four owner capabilities named in the proposal.
