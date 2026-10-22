# 09: Centralize engine capabilities and batch concurrency

**What to build:** Translation-engine metadata and the maximum page concurrency have one authoritative definition shared by the pipeline, services, and settings UI.

**Blocked by:** 08: Make cache identity and secret boundaries explicit.

**Status:** ready-for-agent

- [ ] Engine capability, credential, and display decisions cannot drift across UI and service construction.
- [ ] Every batch scheduling path uses one named three-page limit.
- [ ] Existing engine routing and batch behaviour remain covered by product tests.
- [ ] An intentional registry or concurrency-limit regression makes focused tests red and restoration green.

