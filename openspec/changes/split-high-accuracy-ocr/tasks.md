## 1. Scenario Inventory

- [ ] 1.1 Export the current `high-accuracy-ocr` requirement and scenario names before archive; the baseline MUST contain 10 requirements and 61 scenarios.
- [ ] 1.2 Compare the original scenario list against the four owner specs and confirm every original scenario appears in exactly one owner spec.
- [ ] 1.3 Confirm the deterministic `ModelDownloadState` + `paddleocr.enabled` state-machine table is present under `local-model-lifecycle` with unchanged states, events, side effects, and valid combinations.
- [ ] 1.4 Confirm the six stable PaddleOCR error-code strings are present under `paddleocr-error-contract` with unchanged spelling.
- [ ] 1.5 Confirm the owner-spec scenario counts are exactly: `local-model-lifecycle` 27, `paddleocr-recognizer` 20, `paddleocr-error-contract` 6, and `model-conversion-tooling` 8.

## 2. Spec Structure

- [ ] 2.1 Check `local-model-lifecycle/spec.md` contains no PaddleOCR inference, decode-loop, MLX GPU cache cleanup, localization mapping, or conversion-tooling requirements.
- [ ] 2.2 Check `paddleocr-recognizer/spec.md` contains no download, checksum verification, deletion, launch verification, `UserDefaults` state-machine table, localization mapping, or conversion-tooling requirements.
- [ ] 2.3 Check `paddleocr-error-contract/spec.md` contains no lifecycle state transitions, recognizer runtime behavior, GPU cache cleanup, or conversion-tooling requirements.
- [ ] 2.4 Check `model-conversion-tooling/spec.md` contains no app runtime lifecycle, OCR routing, recognizer memory-management, GPU cache cleanup, or user-facing error-code requirements.
- [ ] 2.5 Check `high-accuracy-ocr/spec.md` contains only the umbrella delegation requirement plus REMOVED requirement stubs pointing to the exact owner requirement names.

## 3. Test Mapping

- [ ] 3.1 Map `local-model-lifecycle` scenarios to existing `DeviceCapabilityServiceTests`, `ModelDownloadServiceTests`, and PaddleOCR settings tests.
- [ ] 3.2 Map `paddleocr-recognizer` scenarios to existing `PaddleOCRVLRecognizerTests`, `DefaultPaddleOCREngineTests`, `MultimodalPositionIdsTests`, and relevant `OCRRouterTests`.
- [ ] 3.3 Map `paddleocr-error-contract` scenarios to existing `OCRRouterTests` stable error-code and localization-code separation tests.
- [ ] 3.4 Map `model-conversion-tooling` scenarios to existing `PaddleOCRProductionParityDiagnosticTests`, `PaddleOCRVerificationTests`, and `scripts/convert_model/` verification commands.
- [ ] 3.5 Record any missing lifecycle, recognizer, error-contract, or tooling coverage as follow-up test tasks scoped to this change; do not include unrelated translation UI or image viewer gaps.

## 4. Validation

- [ ] 4.1 Run `openspec validate split-high-accuracy-ocr --strict` and resolve any schema or delta issues.
- [ ] 4.2 After archiving, run `openspec validate local-model-lifecycle --strict`.
- [ ] 4.3 After archiving, run `openspec validate paddleocr-recognizer --strict`.
- [ ] 4.4 After archiving, run `openspec validate paddleocr-error-contract --strict`.
- [ ] 4.5 After archiving, run `openspec validate model-conversion-tooling --strict`.
- [ ] 4.6 After archiving, run `openspec validate high-accuracy-ocr --strict`.

## 5. Archive Preparation

- [ ] 5.1 Archive `split-high-accuracy-ocr` only after scenario inventory, test mapping, and strict validation are complete.
- [ ] 5.2 Re-check `openspec/specs/` for stale references that still describe `high-accuracy-ocr` as owner of lifecycle, recognizer, error-contract, or tooling details.
- [ ] 5.3 Update `PLAN.md` Phase 1 status after the archive succeeds.
- [ ] 5.4 Leave Phase 2 work on duplicate `paddleocr.enabled` rules in `ocr-routing`, `settings-management`, and `manga-ocr` unstarted until `local-model-lifecycle` is archived.
