# 02: Select an account-available ChatGPT Plan model

**What to build:** A connected user can choose the ChatGPT Plan model used for
translation from the account's current available-model catalog in the same
Settings section.

**Blocked by:** 01: Authorize and disconnect a ChatGPT Plan account.

**Status:** ready-for-agent

- [ ] Settings loads the connected account's displayable model catalog, shows
  a selectable default, and preserves an explicit model choice across launches.
- [ ] Catalog loading follows the existing Copilot-style five-minute cache and
  exposes a retry action on failure.
- [ ] A saved model that is no longer available is never silently replaced; a
  later translation reports the ordinary provider failure.
- [ ] Tests cover catalog filtering, caching, persisted selection, failure, and
  retry behavior without real network access.
