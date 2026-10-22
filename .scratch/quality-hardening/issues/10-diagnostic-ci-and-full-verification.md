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

- `quality.yml` provides the pull-request fast lane: the normal `MangaTranslator` scheme and repository validator only. No GitHub-hosted OCR diagnostic workflow is committed because the repository has no tracked benchmark corpus, model, or parity artifacts.
- The repository validator parses the JSON-form YAML pull-request workflow contract and fails closed if its trigger or required checks are missing. Fixture coverage demonstrates the red condition by removing the workflow; the committed workflow-contract test restores green.
- Retired-test red/green evidence is recorded in tickets 03, 04, 06, and 07. Tickets 08 and 09 add domain contracts but do not retire source-text tests.
- External governance remains required: authenticated API inspection on 2026-10-22 returned an empty repository ruleset list and `404 Branch not protected` for `main`. A repository administrator must configure `main` protection or a ruleset requiring the stable `MangaTranslator tests` and `Repository validation` checks from `PR Quality`.
- Paddle parity is deliberately local-only until a self-hosted runner or an approved external artifact/model source exists. The repository has no self-hosted runner, and `examples/*` plus `.artifacts/paddleocr/` are not tracked, so a GitHub-hosted job could not produce meaningful parity evidence without uploading local data.
- GitHub-hosted OCR benchmark CI was intentionally removed: without a tracked image corpus it would be non-evidentiary. Restore it only with an approved public corpus, external artifact source, or capable self-hosted runner.

