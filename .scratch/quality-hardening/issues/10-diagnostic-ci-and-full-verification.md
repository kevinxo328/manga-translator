# 10: Split OCR diagnostic CI and verify the quality system end to end

**What to build:** Heavy OCR quality diagnostics remain available without slowing PRs, and maintainers have evidence that every new quality gate and migrated test protects the intended behaviour.

**Blocked by:** 01: Establish the PR quality gate; 03: Replace logging source scans with a logging-policy validator; 04: Replace project-text tests with structured project contracts; 06: Replace debug-log and toolbar implementation-text tests; 07: Replace Copilot Settings implementation-text tests; 08: Make cache identity and secret boundaries explicit; 09: Centralize engine capabilities and batch concurrency.

**Status:** blocked

- [ ] OCR benchmark and Paddle parity diagnostics have scheduled and manual execution paths with their inputs documented. (Blocked: no runner may access the local PaddleOCR model and parity artifacts.)
- [x] The PR lane remains limited to the fast required checks.
- [x] Each retired test has recorded red-break/restore-green evidence from its successor.
- [x] The final normal suite and all local validators pass.
- [x] Any unavailable external ruleset authority is reported precisely rather than hidden.

## Comments

- `quality.yml` provides the pull-request fast lane: the normal `MangaTranslator` scheme and repository validator only. `ocr-diagnostics.yml` provides weekly Monday 03:00 UTC scheduling and `workflow_dispatch` for `OCRBenchmark`; `docs/quality-diagnostics.md` records benchmark inputs and the local-only Paddle parity procedure.
- The repository validator parses these JSON-form YAML workflow contracts and fails closed if the PR trigger/checks, benchmark triggers/scheme, or diagnostics documentation are missing. Fixture coverage demonstrates the red condition by removing the diagnostic workflow; the committed workflow-contract test restores green.
- Retired-test red/green evidence is recorded in tickets 03, 04, 06, and 07. Tickets 08 and 09 add domain contracts but do not retire source-text tests.
- External governance remains required: authenticated API inspection on 2026-10-22 returned an empty repository ruleset list and `404 Branch not protected` for `main`. A repository administrator must configure `main` protection or a ruleset requiring the stable `MangaTranslator tests` and `Repository validation` checks from `PR Quality`.
- Paddle parity is deliberately local-only until a self-hosted runner or an approved external artifact/model source exists. The repository has no self-hosted runner, and `examples/*` plus `.artifacts/paddleocr/` are not tracked, so a GitHub-hosted job could not produce meaningful parity evidence without uploading local data.
- The hosted OCR benchmark path is scheduled and manually runnable but currently has no tracked image corpus; it is non-evidentiary until an approved public corpus or artifact source is configured.

