#!/usr/bin/env bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ──────────────────────────────────────────────────────────────────────────────
# Filter: only run xcodebuild test for Swift / Xcode-relevant edits inside the
# project. Everything else (markdown, Python spikes, files under ~/.claude or
# /tmp, generated artifacts) returns immediately.
# ──────────────────────────────────────────────────────────────────────────────

# Hook stdin payload is JSON; capture once and read fields from it.
hook_input=$(cat)
file_path=$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')

# Defensive: if we cannot determine the file, do not block — just exit.
[ -z "$file_path" ] && exit 0

# Only consider files inside this repository.
case "$file_path" in
  "$PROJECT_ROOT"/*) ;;
  *) exit 0 ;;
esac

# Skip generated / cache / dev directories even if they live inside the repo.
case "$file_path" in
  "$PROJECT_ROOT"/.git/*)             exit 0 ;;
  "$PROJECT_ROOT"/.build/*)           exit 0 ;;
  "$PROJECT_ROOT"/.xcodebuild-env/*)  exit 0 ;;
  "$PROJECT_ROOT"/.swiftpm/*)         exit 0 ;;
  "$PROJECT_ROOT"/DerivedData/*)      exit 0 ;;
  "$PROJECT_ROOT"/examples/*)         exit 0 ;;
  "$PROJECT_ROOT"/.venv/*)            exit 0 ;;
  "$PROJECT_ROOT"/node_modules/*)     exit 0 ;;
esac

# Allowlist of Swift / Xcode file patterns that affect a build or test run.
case "$file_path" in
  *.swift|*.metal|*.h|*.m|*.mm) ;;
  *.xcconfig) ;;
  */Package.swift|*/Package.resolved) ;;
  *.xcodeproj/*|*.xcworkspace/*) ;;
  *Info.plist|*.entitlements) ;;
  *.storyboard|*.xib) ;;
  *.xcassets/*) ;;
  *) exit 0 ;;
esac

# ──────────────────────────────────────────────────────────────────────────────
# Actual test run (unchanged).
# ──────────────────────────────────────────────────────────────────────────────

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
