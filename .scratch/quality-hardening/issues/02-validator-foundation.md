# 02: Build the repository-local validator foundation

**What to build:** Maintainers can run one versioned local command that reports policy violations deterministically and can be used as a fail-closed CI check.

**Blocked by:** None (can start immediately).

**Status:** claimed

- [ ] The validator has a stable command-line entry point and machine-readable failure output.
- [ ] Fixture tests prove accepted and rejected policy examples.
- [ ] The command succeeds against the current repository before downstream rules are added.
- [ ] A deliberately invalid fixture makes the validator fail, and restoration makes it pass.

