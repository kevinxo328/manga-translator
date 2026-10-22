# 03: Replace logging source scans with a logging-policy validator

**What to build:** Direct production logging bypasses are rejected by a structural repository rule, while supported logging wrappers remain usable.

**Blocked by:** 02: Build the repository-local validator foundation.

**Status:** ready-for-agent

- [ ] Bare print, NSLog, and direct logger construction are rejected outside explicit supported boundaries.
- [ ] The policy is based on source structure rather than line-oriented substring scanning.
- [ ] A temporary direct logging violation turns the replacement check red; restoring it returns green.
- [ ] The obsolete logging guard test is removed only after the replacement is proven.

## Comments

- Verification: adding `print("logging-policy-probe")` to `BaseURLValidator` made the validator return `logging.direct-print`; removing that exact probe returned the validator to green. The focused `BaseURLValidatorTests` Xcode run passed after restoration.

