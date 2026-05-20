## Why

`settings-management/spec.md` is ~200 lines that mix generic settings infrastructure (UserDefaults, Keychain, Cmd+, shared `PreferencesService`) with capability-specific UI rules for high-accuracy OCR, debug logs, Copilot, auto-update, OpenAI Compatible, and capability-specific UserDefaults keys. Every capability tweak ripples back through this spec, and the same rules are restated in their owner specs — making `settings-management` the wrong place to source the contract. Refactoring it to a thin generic layer aligns with PLAN.md issue 6 and lets each capability own its complete settings story.

## What Changes

### Moves from `settings-management` to other specs

1. **All High-Accuracy OCR Settings UI → `local-model-lifecycle`**
   - Move `Requirement: High-accuracy OCR settings section` (Apple Silicon visibility, state-driven button states, 6 scenarios) to `local-model-lifecycle`.
   - Move `Requirement: Confirm before deleting model data` (confirmation dialog, 2 scenarios) to `local-model-lifecycle`.
   - Move `Requirement: Persist high-accuracy OCR preference` (UserDefaults `paddleocr.enabled` key, recognizer-reset notification, 3 remaining scenarios: "Preference persists across launches", "Enable blocked when model is absent", "Enable blocked after failed verification") to `local-model-lifecycle`. Remove the embedded duplicate of recognizer-reset behavior already owned by `ocr-routing`'s "Reset recognizer on engine switch".

2. **Debug tab UI → `debug-log-management`**
   - Move the "Debug tab" clause from the long `Requirement: Settings UI` requirement text, plus 13 Debug-tab scenarios (Open Debug tab, Filter logs from Settings, Debug tab uses bounded list, Debug tab preserves Settings window size, Load more logs, Open log detail, Content text stays out of rows, Search is debounced, Clear logs from Settings, Clear confirmation shows count, Clear preserves filters, Export logs from Settings, Export uses save panel) to `debug-log-management`.

3. **GitHub Copilot Settings UI → `copilot-model-management`**
   - Move the Copilot clause from the `Settings UI` requirement text (Copilot section in API Keys tab, engine picker gating) plus 4 scenarios (GitHub Copilot section — CLI detected / CLI not installed / not logged in, Engine picker hides Copilot when unavailable) to `copilot-model-management`.
   - Move the `copilotModel` UserDefaults key reference from the `Store user preferences` requirement enumeration into `copilot-model-management` (which already owns the `Copilot model selection persistence` requirement with the `copilotModel` key).

4. **Auto-update Settings UI → `auto-update`**
   - Move the Updates-section clause from the `Settings UI` requirement text plus 3 scenarios (Toggle automatic updates, Manual update check from settings, UpdateSettingsView ViewModel survives parent re-render) to `auto-update`.

5. **OpenAI Compatible Settings UI → `openai-compatible-config`**
   - Move the "OpenAI Compatible" rename clause and Base URL / Model / Reset clause from the `Settings UI` requirement text plus 1 scenario (OpenAI Compatible section layout) to `openai-compatible-config`.
   - Move the OpenAI base URL and OpenAI model name keys from the `Store user preferences` requirement enumeration and the scenario "OpenAI base URL persists across launches" to `openai-compatible-config` (which already owns persistence statements for these in its own requirements).
   - Move the live-apply scenario "Model change applies to next translation" (currently using OpenAI model as example) to `openai-compatible-config`.

### Retained in `settings-management`

- `Requirement: Store user preferences in UserDefaults` — pared down to cross-capability keys only: default source language, default target language, default translation engine, concurrent translation limit. Capability-specific keys (OpenAI base URL/model, Copilot model name, `paddleocr.enabled`) move to their owners.
- `Requirement: Store API keys in Keychain` — generic Keychain `serviceName` policy.
- `Requirement: Settings UI` — pared down to: settings window accessible via Cmd+,, tab structure (no capability-specific UI rules), language pickers display format using flag emoji and full English names. All capability-specific UI clauses removed.
- `Requirement: Validate API key presence before translation` — generic API-key gate.
- `Requirement: Settings changes apply immediately to active translation session` — keeps the shared `PreferencesService` instance contract and the 2 generic scenarios (Language change applies to next translation, Engine change applies to next translation). The Model change scenario moves to `openai-compatible-config`.

### Constraints preserved verbatim

- All `UserDefaults` key names (`paddleocr.enabled`, `paddleocr.model.downloaded`, `copilotModel`).
- Keychain `serviceName` constant `com.chunweiliu.MangaTranslator`.
- Every moved scenario's WHEN/THEN text is preserved exactly — only the file location changes.
- No production code changes; no behavior change visible to users.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `settings-management`: Reduced to generic settings infrastructure. 8 scenarios remain across 5 retained requirements (Store user preferences, Store API keys, Settings UI, Validate API key, Settings changes apply immediately).
- `local-model-lifecycle`: Gains 3 requirements (High-accuracy OCR settings section, Confirm before deleting model data, Persist high-accuracy OCR preference) with 11 scenarios total (6 + 2 + 3).
- `debug-log-management`: Gains 1 requirement (Debug tab UI in Settings) with 13 scenarios.
- `copilot-model-management`: Gains 1 requirement (Copilot section in Settings) with 4 scenarios. Existing `Copilot model selection persistence` requirement absorbs the `copilotModel` key reference removed from `settings-management`.
- `auto-update`: Gains 1 requirement (Updates section in Settings) with 3 scenarios.
- `openai-compatible-config`: Gains 1 requirement (OpenAI Compatible section UI in Settings) with 1 scenario, and inherits the "OpenAI base URL persists across launches" and "Model change applies to next translation" scenarios as part of its persistence and live-apply requirements.

## Impact

- Spec-only restructure. No production code changes.
- No `UserDefaults` key changes; no Keychain `serviceName` change; no behavior change visible to users.
- Contributors editing capability-specific Settings UI now edit the owner capability, not `settings-management`.
- Cross-references from archived changes may point to old `settings-management` locations — those are historical artifacts and stay untouched per OpenSpec convention.
- Pre-existing format warnings on `settings-management/spec.md` (Purpose section too brief, one Requirement text > 500 chars) are cleared incidentally as part of this change's post-archive Purpose rewrite and the natural shrinkage of the `Settings UI` requirement text; the broader format-normalisation effort remains tracked under PLAN.md issue 8.
