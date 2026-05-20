## Context

`settings-management/spec.md` currently has 207 lines mixing generic settings infrastructure (UserDefaults storage policy, Keychain `serviceName` policy, Cmd+, opening, shared `PreferencesService` instance contract, API-key-required check, language picker display format) with capability-specific UI rules for high-accuracy OCR, debug logs, Copilot, auto-update, OpenAI Compatible, and capability-specific UserDefaults keys. Phase 2 of PLAN.md already removed the worst overlap with `local-model-lifecycle`. This change executes PLAN.md issue 6: each capability-specific clause and scenario moves to its owner spec; `settings-management` retains only generic infrastructure.

All target capability specs (`local-model-lifecycle`, `debug-log-management`, `copilot-model-management`, `auto-update`, `openai-compatible-config`) already exist after the Phase 0/1 work.

## Goals / Non-Goals

**Goals:**

- Move every capability-specific Settings UI requirement and scenario from `settings-management` to the owner capability.
- Preserve every moved scenario's WHEN/THEN behavior exactly. Adjust cross-capability references only when a moved sentence would become self-referential in the new location.
- Preserve every stable string constant: `UserDefaults` keys (`paddleocr.enabled`, `paddleocr.model.downloaded`, `copilotModel`), Keychain `serviceName` (`com.chunweiliu.MangaTranslator`), error code names.
- Keep total scenario count unchanged across the 6 affected specs (parity check is part of acceptance).
- Validate every affected spec with `openspec validate --strict` after deltas are applied.

**Non-Goals:**

- Production code changes. This is a spec-only restructure.
- The broader format-normalisation work tracked under PLAN.md issue 8 (e.g., harmonising `# Title` vs `## Purpose` across all specs, splitting any oversized requirements in other capabilities). The two `settings-management` format warnings are cleared as an incidental side-effect of this change's structural moves (see D8) — they are not the goal but they fall out naturally.
- Adding new behavior, new requirements that weren't already implied, or rewording behavioral statements.
- Touching archived changes that reference old `settings-management` locations — archives are immutable historical artifacts per OpenSpec convention.

## Decisions

### D1. High-Accuracy OCR Settings UI lives in `local-model-lifecycle`

Both the "High-accuracy OCR settings section" requirement (Apple Silicon visibility, state-driven buttons) and the "Confirm before deleting model data" requirement gate operations defined on the lifecycle: device capability, `ModelDownloadState` transitions, and `delete()`. `paddleocr-recognizer` was the alternative, but its Purpose is "PaddleOCR-VL recognizer runtime behavior" — inference-time mechanics, no UI. Putting Settings UI scenarios into `paddleocr-recognizer` would broaden its scope incoherently. `local-model-lifecycle` already owns the states being displayed; it should own how Settings users observe and interact with those states.

This also means `Requirement: Persist high-accuracy OCR preference` (UserDefaults `paddleocr.enabled` key, 3 scenarios) lands in `local-model-lifecycle`, alongside its state machine.

### D2. `Store user preferences in UserDefaults` keeps cross-capability keys only

Capability-specific keys (`OpenAI base URL`, `OpenAI model name`, `copilotModel`, `paddleocr.enabled`) move to their owner specs, which already (or will) carry the persistence requirement for each. The settings-management requirement retains the cross-capability keys that no single capability owns: `default source language`, `default target language`, `default translation engine`, `concurrent translation limit`. The "Preferences persist across launches" scenario (language pair) stays; "OpenAI base URL persists across launches" moves to `openai-compatible-config` as an additional scenario under its existing "Configurable base URL for OpenAI-compatible API" requirement.

### D3. `Settings UI` requirement is split, not preserved as a single long requirement

The current 500+ character `Settings UI` requirement is the dumping ground for capability-specific UI clauses. Rather than try to preserve it as one requirement with most scenarios removed, the new `settings-management` `Settings UI` requirement is reformulated to cover only:

- Cmd+, opening of the settings window.
- The window has a tabbed structure; each tab's content is owned by the corresponding capability.
- Language pickers across all engines display languages using flag emoji and full English names.

Kept scenarios: `Open settings`, `Language picker display codes`. The "Open settings" scenario's THEN line is trimmed: the original "showing API key fields, default preferences, and update preferences" enumerates capability-specific content that is no longer this requirement's concern. The trim is a structural consequence of the move, not a behavior change — capability-owned scenarios in their target specs cover the content.

### D4. `Settings changes apply immediately` keeps the shared-instance contract; Model scenario migrates

The shared `PreferencesService` instance contract is genuinely cross-cutting. Language and engine change scenarios are generic (any preference flowing through the shared instance) and stay. The `Model change applies to next translation` scenario specifically uses the OpenAI model field — it's an OpenAI-specific live-apply assertion. It moves to `openai-compatible-config` as an additional scenario under that capability's "Configurable model name for OpenAI-compatible API" requirement.

### D5. Moves use `## REMOVED` + `## ADDED` deltas; no `MODIFIED` for the moved requirements themselves

Three requirements move whole from `settings-management` to `local-model-lifecycle` (`High-accuracy OCR settings section`, `Confirm before deleting model data`, `Persist high-accuracy OCR preference`). Each is REMOVED in `settings-management`'s delta and ADDED verbatim in `local-model-lifecycle`'s delta. This makes the move auditable: the same requirement appears identically on both sides of the diff.

The three SHRINKING requirements in `settings-management` (`Store user preferences`, `Settings UI`, `Settings changes apply immediately`) use `## MODIFIED Requirements` with the full new text and remaining scenarios.

The four ADDITIONS to consumer specs (one new requirement each in `debug-log-management`, `copilot-model-management`, `auto-update`, `openai-compatible-config`) use `## ADDED Requirements`. The two scenario-only additions to `openai-compatible-config`'s existing requirements (base URL persists across launches, model change applies to next translation) use `## MODIFIED Requirements` with the full requirement text plus the appended scenarios.

### D6. Scenario titles are kept verbatim, including phrases like "from Settings"

Several scenarios have titles like `Filter logs from Settings`, `Clear logs from Settings`, `Export logs from Settings`. After moving to `debug-log-management`, "from Settings" is contextually less informative (the scenario is *only* about Settings UI). But the title is an identifier referenced by readers and possibly by test names; preserving it avoids drift risk. The phrase still reads correctly (Settings is the *invocation surface*, not the *location of the test*).

The one exception: cross-capability references inside WHEN/THEN that become self-referential after the move are rephrased minimally. Specifically, the two `Enable blocked` scenarios from Phase 2 reference "`local-model-lifecycle` rejects the transition (per its state machine)" — after moving INTO `local-model-lifecycle`, this becomes "the state machine of this capability rejects the transition" or "the transition is rejected per the state machine table (this requirement)". Semantic content preserved; only the deictic reference adjusts.

### D7. Scenario count parity is verified by table, before and after

To avoid silent loss of tests, the tasks artifact produces a before/after table:

| Spec | Before | Moves out | Moves in | After |
| --- | --- | --- | --- | --- |
| settings-management | 42 | -34 | 0 | 8 |
| local-model-lifecycle | 27 | 0 | +11 | 38 |
| debug-log-management | 54 | 0 | +13 | 67 |
| copilot-model-management | 7 | 0 | +4 | 11 |
| auto-update | 11 | 0 | +3 | 14 |
| openai-compatible-config | 9 | 0 | +3 | 12 |

Sum of "Moves out" from settings (34) equals sum of "Moves in" across the 5 targets (11+13+4+3+3 = 34). Settings retained scenario count after subtraction (42 − 34 = 8) matches the kept set: `Preferences persist across launches`, `Save API key`, `Retrieve API key`, `Open settings`, `Language picker display codes`, `Missing API key`, `Language change applies to next translation`, `Engine change applies to next translation`.

Baselines were captured by `grep -c '^#### Scenario:' openspec/specs/<spec>/spec.md` at the start of this change.

## Risks / Trade-offs

- [Risk] Spec readers searching for "settings" or "Cmd+," may not find capability-specific UI in `settings-management` anymore. → Mitigation: the new `settings-management` `Settings UI` requirement explicitly states "Each tab's content is owned by the corresponding capability." Cross-references in proposal.md make the new ownership map searchable.

- [Risk] Future contributors may try to re-add capability-specific UI to `settings-management` as the path of least resistance. → Mitigation: `settings-management/Purpose` is updated to emphasize "generic infrastructure only"; the `Settings UI` requirement repeats the principle.

- [Risk] Moved cross-capability references (D6's "self-reference" cases) could drift from the spirit of the original. → Mitigation: limited to two scenarios both inside the same requirement, both with surrounding context that makes the intent obvious; both rephrasings are reviewed in the specs delta diff.

- [Risk] Pre-existing `settings-management` format warnings (Purpose too brief, Requirement >500 chars) may worsen or improve unpredictably. → Mitigation: the new `Settings UI` text is intentionally short (~350 chars), which should clear the >500 char warning. Purpose is reworded slightly (D8 below) to clear the "<50 chars" warning. These improvements are incidental to the move; they're not new behavioral content.

### D8 (incidental). `settings-management/Purpose` is reworded to clear the pre-existing format warning

Current: `User preferences persistence and settings UI.` (37 chars, under the 50-char floor.) New: `Generic settings infrastructure: UserDefaults storage policy, Keychain serviceName policy, settings window opened via Cmd+,, shared PreferencesService instance, API-key-required gate, and language picker display format used by all translation engines.` (~250 chars.) This is a documentation improvement, not a behavioral change; it incidentally clears the pre-existing warning without expanding scope.

## Migration Plan

This is a spec-only change. No code migration, no deployment risk, no rollback story.

Apply order:

1. Edit deltas under `openspec/changes/slim-settings-management/specs/` for all 6 affected capabilities.
2. Run `openspec validate slim-settings-management --strict`.
3. Run `openspec validate <each-affected-capability> --strict` for parity confirmation.
4. Verify scenario count parity by `grep -c "^#### Scenario:" openspec/specs/<each>/spec.md` before and after archive.
5. Archive once `openspec validate --strict` passes.

Rollback: revert the archive commit. `git revert` brings every moved scenario back to `settings-management` in one diff.

## Open Questions

None. D1–D8 resolve every directional decision needed to apply the deltas.
