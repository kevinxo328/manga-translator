#!/usr/bin/env bash
set -uo pipefail

HOOK_INPUT="$(cat)"

SESSION_ID=$(
  printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except Exception:
    print('unknown')
    raise SystemExit(0)
session_id = payload.get('sessionId') or payload.get('session_id') or 'unknown'
print(session_id if isinstance(session_id, str) else 'unknown')
"
)

SAFE_SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')
FAILURE_FILE="/tmp/copilot-post-edit-failure-${SAFE_SESSION_ID}.log"

if [ ! -s "$FAILURE_FILE" ]; then
  exit 0
fi

summary=$(cat "$FAILURE_FILE")
rm -f "$FAILURE_FILE"

printf '%s' "$summary" | python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({
  'decision': 'block',
  'reason': 'Tests FAILED after edit. Fix the following errors before proceeding:\\n\\n' + text
}))
"
