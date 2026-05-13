#!/usr/bin/env bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

output=$(xcodebuild test \
  -project "$PROJECT_ROOT/MangaTranslator.xcodeproj" \
  -scheme MangaTranslator \
  -destination 'platform=macOS' \
  -quiet 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
  # Extract relevant failure lines
  summary=$(echo "$output" | grep -E "(error:|FAILED|XCTAssert|Test.*failed)" | tail -30)
  [ -z "$summary" ] && summary=$(echo "$output" | tail -30)

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
fi
