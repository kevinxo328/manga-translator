# 03: Replace logging source scans with a logging-policy validator

**What to build:** Direct production logging bypasses are rejected by a structural repository rule, while supported logging wrappers remain usable.

**Blocked by:** 02: Build the repository-local validator foundation.

**Status:** resolved

- [x] Bare print, NSLog, and direct logger construction are rejected outside explicit supported boundaries.
- [x] The policy is based on source structure rather than line-oriented substring scanning.
- [x] A temporary direct logging violation turns the replacement check red; restoring it returns green.
- [x] The obsolete logging guard test is removed only after the replacement is proven.

## Comments

- Verification: adding `print`, `NSLog`, and `Logger` probes to `BaseURLValidator` made the validator return `logging.direct-print`, `logging.direct-nslog`, and `logging.direct-logger`; removing those exact probes returned the validator to green. The focused `BaseURLValidatorTests` Xcode run passed after restoration.
- Review fixes: missing source directories now produce `source.directory.unreadable`, and fixture coverage proves only `Services/DebugLogger.swift` and `Services/DebugLogStore.swift` are exempt. `swift test --package-path Tools/RepositoryValidator` passed with 12 tests; the validator also passed against the repository root.

