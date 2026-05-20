## 1. Baseline parity capture

- [ ] 1.1 Capture scenario count for each affected spec before archive: `grep -c '^#### Scenario:' openspec/specs/{settings-management,local-model-lifecycle,debug-log-management,copilot-model-management,auto-update,openai-compatible-config}/spec.md` and save the baseline. Expected: settings-management=42, local-model-lifecycle=27, debug-log-management=54, copilot-model-management=7, auto-update=11, openai-compatible-config=9.

## 2. Validate change deltas

- [ ] 2.1 `openspec validate slim-settings-management --strict` returns "is valid".
- [ ] 2.2 Visually diff the 6 delta files under `openspec/changes/slim-settings-management/specs/` against the source `openspec/specs/settings-management/spec.md` to confirm every moved scenario's WHEN/THEN text is preserved verbatim except for the two self-reference rephrasings called out in design D6 (`Enable blocked when model is absent`, `Enable blocked after failed verification`).

## 3. Archive the change

- [ ] 3.1 Archive via `openspec archive slim-settings-management` (or the equivalent skill); confirm the timestamp prefix matches the actual archive date.
- [ ] 3.2 Re-run `openspec validate <each-of-6-capabilities> --strict` post-archive. Allowed warnings on `settings-management`: pre-existing Purpose-too-brief and Requirement-too-long warnings (PLAN.md issue 8). No new warnings or errors elsewhere.

## 4. Post-archive parity verification

- [ ] 4.1 Re-count scenarios on each affected spec after archive. Expected: settings-management=8, local-model-lifecycle=27+11=38, debug-log-management=54+13=67, copilot-model-management=7+4=11, auto-update=11+3=14, openai-compatible-config=9+3=12.
- [ ] 4.2 Confirm settings-management loss (42-8=34) equals the sum of moves into the 5 targets (11+13+4+3+3=34). Any mismatch means a scenario was dropped or duplicated — investigate before continuing.
- [ ] 4.3 `grep -n 'paddleocr.enabled\|copilotModel' openspec/specs/settings-management/spec.md` returns no matches (capability-specific keys fully moved out).
- [ ] 4.4 `grep -n 'High-Accuracy OCR\|Debug tab\|GitHub Copilot\|OpenAI Compatible\|Updates section' openspec/specs/settings-management/spec.md` returns no matches except for the kept `Settings UI` requirement's tab-owner pointer list (which names the capabilities but does not specify their UI).

## 5. Incidental Purpose update (design D8)

- [ ] 5.1 After archive sync, manually update `openspec/specs/settings-management/spec.md` Purpose to: "Generic settings infrastructure: UserDefaults storage policy, Keychain serviceName policy, settings window opened via Cmd+,, shared PreferencesService instance, API-key-required gate, and language picker display format used by all translation engines." This clears the pre-existing "Purpose section too brief" warning.
- [ ] 5.2 `openspec validate settings-management --strict` shows the Purpose warning is cleared. The Requirement-too-long warning should also be cleared because the new `Settings UI` requirement text is ~350 chars.

## 6. Update PLAN.md

- [ ] 6.1 Mark Phase 5 (`slim-settings-management`) as `[x]` in `PLAN.md`'s "執行順序" section.
- [ ] 6.2 Update issue 6 work-items to `[x]` with one-sentence summary of the archive outcome.
