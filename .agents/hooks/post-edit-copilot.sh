#!/usr/bin/env bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_INPUT="$(cat)"
SESSION_ID="unknown"
FAILURE_FILE="/tmp/copilot-post-edit-failure-unknown.log"

should_run_tests=1
if [ -n "${HOOK_INPUT//[[:space:]]/}" ]; then
  parsed=$(
    printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except Exception:
    print('__parse_error__\\tunknown')
    raise SystemExit(0)
tool_name = payload.get('toolName') or payload.get('tool_name') or ''
session_id = payload.get('sessionId') or payload.get('session_id') or 'unknown'
if not isinstance(session_id, str):
    session_id = 'unknown'
print((tool_name if isinstance(tool_name, str) else '').strip().lower() + '\\t' + session_id)
"
  )
  tool_name=${parsed%%$'\t'*}
  SESSION_ID=${parsed#*$'\t'}
  SAFE_SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')
  FAILURE_FILE="/tmp/copilot-post-edit-failure-${SAFE_SESSION_ID}.log"

  case "$tool_name" in
    edit|create|write|replace|write_file|apply_patch) ;;
    __parse_error__|"") ;;
    *) should_run_tests=0 ;;
  esac
fi

if [ "$should_run_tests" -ne 1 ]; then
  rm -f "$FAILURE_FILE"
  exit 0
fi

output=$(xcodebuild test \
  -project "$PROJECT_ROOT/MangaTranslator.xcodeproj" \
  -scheme MangaTranslator \
  -destination 'platform=macOS' \
  -quiet 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
  summary=$(echo "$output" | grep -E "(error:|FAILED|XCTAssert|Test.*failed)" | tail -30)
  [ -z "$summary" ] && summary=$(echo "$output" | tail -30)
  printf '%s\n' "$summary" > "$FAILURE_FILE"

  printf '%s' "$summary" | python3 -c "
import sys, json
text = sys.stdin.read()
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PostToolUse',
    'additionalContext': 'Tests FAILED after edit. Fix the following errors before proceeding:\n\n' + text
  }
}))
"

  {
    echo "Tests FAILED after edit. Fix the following errors before proceeding:"
    echo
    printf '%s\n' "$summary"
  } >&2

  exit 2
fi

rm -f "$FAILURE_FILE"
