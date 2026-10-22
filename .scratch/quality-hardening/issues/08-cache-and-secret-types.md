# 08: Make cache identity and secret boundaries explicit

**What to build:** Cache access requires complete identity and credential-handling APIs prevent accidental persistence or diagnostic exposure of raw provider secrets.

**Blocked by:** 01: Establish the PR quality gate.

**Status:** ready-for-agent

- [ ] Cache identity combines image-content hash with source language, target language, and translation engine in one value.
- [ ] Cache lookup and store cannot accidentally omit or mismatch translation context.
- [ ] Credential persistence and logging boundaries use an explicit secret/API-key type.
- [ ] Existing runtime cache, Keychain, and redaction contracts remain green.
- [ ] Intentional context/secret-boundary regressions make focused successor tests red and restoration green.

