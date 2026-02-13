#!/bin/bash
set -euo pipefail

# Usage: ./scripts/generate_appcast.sh <version> <dmg-path> <ed-signature> <file-size>
# Generates appcast.xml for Sparkle auto-update.

TAG_VERSION="$1"
DMG_PATH="$2"
ED_SIGNATURE="$3"
FILE_SIZE="$4"

# Strip leading "v" prefix for Sparkle version comparison
# Sparkle compares sparkle:shortVersionString against CFBundleShortVersionString (e.g. "1.0.1")
# and sparkle:version against CFBundleVersion (build number)
SHORT_VERSION="${TAG_VERSION#v}"

DMG_FILENAME=$(basename "$DMG_PATH")
DOWNLOAD_URL="https://github.com/kevinxo328/manga-translator/releases/download/${TAG_VERSION}/${DMG_FILENAME}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")

cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MangaTranslator Updates</title>
    <language>en</language>
    <item>
      <title>Version ${SHORT_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${SHORT_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${FILE_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}"
      />
    </item>
  </channel>
</rss>
EOF

echo "Generated appcast.xml for ${TAG_VERSION} (version: ${SHORT_VERSION})"
