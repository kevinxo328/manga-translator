# 02: Build the repository-local validator foundation

**What to build:** Maintainers can run one versioned local command that reports policy violations deterministically and can be used as a fail-closed CI check.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The validator has a stable command-line entry point and machine-readable failure output.
- [x] Fixture tests prove accepted and rejected policy examples.
- [x] The command succeeds against the current repository before downstream rules are added.
- [x] A deliberately invalid fixture makes the validator fail, and restoration makes it pass.

## Comments

- Delivered by `ed2062d` and `90e9f40`: `repository-validator` emits JSON violations and a nonzero exit for invalid roots; fixture and executable tests cover the command contract.

