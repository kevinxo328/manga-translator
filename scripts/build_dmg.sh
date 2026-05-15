#!/bin/bash

# Project configuration
PROJECT_NAME="MangaTranslator"
SCHEME_NAME="MangaTranslator"
BUILD_DIR="build"

echo "🚀 Starting build process..."

# 1. Determine version (strip "v" prefix from git tag if present)
if [ -z "$VERSION" ]; then
    VERSION=$(xcodebuild -showBuildSettings | grep MARKETING_VERSION | tr -d ' ' | cut -d '=' -f2)
else
    VERSION="${VERSION#v}"
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
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${VERSION}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

# 4. Prepare export folder
echo "📂 Preparing export folder..."
EXPORT_PATH="${BUILD_DIR}/export"
mkdir -p "$EXPORT_PATH"
cp -R "${BUILD_DIR}/${PROJECT_NAME}.xcarchive/Products/Applications/${PROJECT_NAME}.app" "$EXPORT_PATH/"

# 4a. Recover SPM resource bundles dropped by the archive flow.
# `xcodebuild archive` builds `mlx-swift_Cmlx.bundle` (which contains
# `default.metallib`) into ArchiveIntermediates/.../UninstalledProducts/
# but does not copy it into the final .app. Without it, MLX aborts on
# the first GPU op with "Failed to load the default metallib".
APP_BUNDLE_PATH="$EXPORT_PATH/${PROJECT_NAME}.app"
APP_RESOURCES="$APP_BUNDLE_PATH/Contents/Resources"
if [ ! -d "$APP_RESOURCES/mlx-swift_Cmlx.bundle" ]; then
    echo "📦 Recovering missing mlx-swift_Cmlx.bundle for MLX..."
    INTERMEDIATE_BUNDLE=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path "*ArchiveIntermediates/${PROJECT_NAME}*UninstalledProducts/macosx/mlx-swift_Cmlx.bundle" \
        -type d 2>/dev/null | head -1)
    if [ -z "$INTERMEDIATE_BUNDLE" ] || [ ! -f "$INTERMEDIATE_BUNDLE/Contents/Resources/default.metallib" ]; then
        echo "❌ Could not locate mlx-swift_Cmlx.bundle in DerivedData. Aborting."
        echo "   Searched: $HOME/Library/Developer/Xcode/DerivedData/*/Build/Intermediates.noindex/ArchiveIntermediates/${PROJECT_NAME}/.../mlx-swift_Cmlx.bundle"
        exit 1
    fi
    cp -R "$INTERMEDIATE_BUNDLE" "$APP_RESOURCES/"
    echo "   ✓ Copied from: $INTERMEDIATE_BUNDLE"
fi

# 4b. Verify the metallib actually exists before signing.
METALLIB_PATH="$APP_RESOURCES/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
if [ ! -f "$METALLIB_PATH" ]; then
    echo "❌ default.metallib missing at $METALLIB_PATH. Aborting."
    exit 1
fi
echo "✅ default.metallib present ($(du -h "$METALLIB_PATH" | cut -f1))"

# 5. Ad-hoc code sign the app to prevent "damaged" error on macOS
echo "🔏 Ad-hoc signing the app..."
codesign --force --deep --sign - "$EXPORT_PATH/${PROJECT_NAME}.app"

# 6. Package into DMG using hdiutil
echo "💿 Generating DMG..."
DMG_FILENAME="${PROJECT_NAME}-${VERSION}.dmg"
hdiutil create -volname "${PROJECT_NAME}" -srcfolder "$EXPORT_PATH" -ov -format UDZO "${BUILD_DIR}/${DMG_FILENAME}"

echo "✅ Success! DMG created at: ${BUILD_DIR}/${DMG_FILENAME}"