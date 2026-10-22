# 10: Split OCR diagnostic CI and verify the quality system end to end

**What to build:** Heavy OCR quality diagnostics remain available without slowing PRs, and maintainers have evidence that every new quality gate and migrated test protects the intended behaviour.

**Blocked by:** 01: Establish the PR quality gate; 03: Replace logging source scans with a logging-policy validator; 04: Replace project-text tests with structured project contracts; 06: Replace debug-log and toolbar implementation-text tests; 07: Replace Copilot Settings implementation-text tests; 08: Make cache identity and secret boundaries explicit; 09: Centralize engine capabilities and batch concurrency.

**Status:** ready-for-agent

- [ ] OCR benchmark and Paddle parity diagnostics have scheduled and manual execution paths with their inputs documented.
- [ ] The PR lane remains limited to the fast required checks.
- [ ] Each retired test has recorded red-break/restore-green evidence from its successor.
- [ ] The final normal suite and all local validators pass.
- [ ] Any unavailable external ruleset authority is reported precisely rather than hidden.

