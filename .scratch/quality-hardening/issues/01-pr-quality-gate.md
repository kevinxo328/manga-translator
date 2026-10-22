# 01: Establish the PR quality gate

**What to build:** Contributors receive a required, deterministic PR result for the normal MangaTranslator suite and repository quality validation before main can be merged.

**Blocked by:** 02: Build the repository-local validator foundation.

**Status:** ready-for-agent

- [ ] A pull request runs the normal MangaTranslator regression suite and the validator entry point.
- [ ] The workflow has stable named checks suitable for a main-branch ruleset.
- [ ] Main requires those checks; if repository authority is unavailable, record the exact external configuration still required.
- [ ] The workflow fails when either the application suite or validator fails.

