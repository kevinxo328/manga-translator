# 01: Authorize and disconnect a ChatGPT Plan account

**What to build:** A user can explicitly connect one ChatGPT account from the
ChatGPT Plan (Preview) section in API Keys, see its verified email, and log out.
The connection uses a secure OAuth lifecycle and logout disconnects the app
from that account.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The user can begin Sign in with ChatGPT only by pressing the Settings
  sign-in control, complete the loopback callback, and see the connected email.
- [ ] Authorization validates transaction state and identity, retains one local
  account session, and refreshes rotating credentials safely.
- [ ] Logout revokes renewable access, clears local credentials, and leaves
  ChatGPT Plan selected rather than switching translation engines.
- [ ] Credentials, OAuth URLs, and account identity do not appear in logs or
  diagnostics; automated tests cover the lifecycle without real network access.
