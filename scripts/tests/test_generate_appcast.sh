#!/bin/bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPORARY_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

cd "$TEMPORARY_DIRECTORY"
"$REPOSITORY_ROOT/scripts/generate_appcast.sh" \
  "v1.6.2" \
  "/tmp/MangaTranslator-1.6.2.dmg" \
  "test-signature" \
  "42"

DESCRIPTION=$(sed -n '/<description><!\[CDATA\[/,/<\/description>/p' appcast.xml)
grep -F '<description><![CDATA[' <<<"$DESCRIPTION"
grep -F '<h2>v1.6.2 (2026-10-24)</h2>' <<<"$DESCRIPTION"
grep -F '<h3>Bug Fixes</h3>' <<<"$DESCRIPTION"
grep -F '<li>Fixed translated text showing literal &quot;\n&quot; instead of actual line breaks in speech bubbles.</li>' <<<"$DESCRIPTION"
xmllint --noout appcast.xml

RENDERED_NOTES=$(printf '### Improvements\n\n- **Fast** & safe\n' | python3 "$REPOSITORY_ROOT/scripts/render_release_notes.py")
grep -F '<h3>Improvements</h3>' <<<"$RENDERED_NOTES"
grep -F '<li><strong>Fast</strong> &amp; safe</li>' <<<"$RENDERED_NOTES"
