#!/bin/bash

# Project configuration
PROJECT_NAME="MangaTranslator"
SCHEME_NAME="MangaTranslator"
BUILD_DIR="build"

echo "🚀 Starting build process..."

# 1. Determine version
if [ -z "$VERSION" ]; then
    VERSION=$(xcodebuild -showBuildSettings | grep MARKETING_VERSION | tr -d ' ' | cut -d '=' -f2)
fi
echo "📦 Version: $VERSION"

# 2. Clean old files
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 3. Build Archive (Skip signing for free accounts / CI environments)
echo "🏗️  Building Release version..."
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -archivePath "${BUILD_DIR}/${PROJECT_NAME}.xcarchive" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

# 4. Prepare export folder
echo "📂 Preparing export folder..."
EXPORT_PATH="${BUILD_DIR}/export"
mkdir -p "$EXPORT_PATH"
cp -R "${BUILD_DIR}/${PROJECT_NAME}.xcarchive/Products/Applications/${PROJECT_NAME}.app" "$EXPORT_PATH/"

# 5. Ad-hoc code sign the app to prevent "damaged" error on macOS
echo "🔏 Ad-hoc signing the app..."
codesign --force --deep --sign - "$EXPORT_PATH/${PROJECT_NAME}.app"

# 6. Package into DMG using hdiutil
echo "💿 Generating DMG..."
DMG_FILENAME="${PROJECT_NAME}-${VERSION}.dmg"
hdiutil create -volname "${PROJECT_NAME}" -srcfolder "$EXPORT_PATH" -ov -format UDZO "${BUILD_DIR}/${DMG_FILENAME}"

echo "✅ Success! DMG created at: ${BUILD_DIR}/${DMG_FILENAME}"